#!/usr/bin/env bash
# Build everything from scratch (or converge an existing setup). Safe to re-run.
source "$(dirname "$0")/lib.sh"

# --- 1. Preflight -----------------------------------------------------------
for cmd in docker kind kubectl helm curl openssl; do
  command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found on PATH (see README prerequisites)"
done
docker info >/dev/null 2>&1 || die "Docker is not running (start Docker Desktop / Colima / the docker service)"

# --- 2. Cluster -------------------------------------------------------------
mkdir -p "$(dirname "$KUBECONFIG")"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "kind cluster '$CLUSTER_NAME' already exists, reusing it"
  kind export kubeconfig --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG" >/dev/null
else
  log "Creating kind cluster '$CLUSTER_NAME'"
  kind create cluster --config "$ROOT_DIR/cluster/kind-config.yaml" --kubeconfig "$KUBECONFIG" --wait 120s
fi

# --- 3. Namespaces ----------------------------------------------------------
log "Applying namespaces"
kubectl apply -f "$ROOT_DIR/k8s/namespaces.yaml"

# --- 4. Technical API password (generated once, never committed) -----------
if [ ! -s "$TECHAPI_PASSWORD_FILE" ]; then
  log "Generating gateway technical API password"
  mkdir -p "$SECRETS_DIR"
  (umask 077 && openssl rand -hex 24 > "$TECHAPI_PASSWORD_FILE")
fi
TECHAPI_PASSWORD="$(cat "$TECHAPI_PASSWORD_FILE")"
# Also published as a Secret so a Prometheus scrape config can reference it.
kubectl -n gravitee create secret generic gateway-techapi-credentials \
  --from-literal=username=admin \
  --from-literal=password="$TECHAPI_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- 5. Gravitee Kubernetes Operator ---------------------------------------
log "Installing Gravitee Kubernetes Operator $GKO_CHART_VERSION"
helm upgrade --install gko gko \
  --repo "$GRAVITEE_HELM_REPO" --version "$GKO_CHART_VERSION" \
  --namespace gko-system \
  --values "$ROOT_DIR/helm/gko-values.yaml" \
  --wait --timeout 5m

# Upstream bug (checked on GKO 4.10 to 4.12.20): the linux/arm64 operator image
# contains an x86-64 binary. On arm64 hosts (Apple Silicon) it only runs reliably
# under Rosetta; under qemu-user it segfaults at random (qemu does not emulate
# x86 memory ordering). Warn instead of failing so Linux/amd64 is unaffected.
NODE_ARCH="$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.architecture}')"
if [ "$NODE_ARCH" = "arm64" ] && \
   ! docker exec "${CLUSTER_NAME}-control-plane" grep -qx enabled /proc/sys/fs/binfmt_misc/rosetta 2>/dev/null; then
  warn "arm64 host without Rosetta: the GKO operator (x86-64 binary) will crash under qemu."
  warn "Enable Rosetta for amd64 emulation (Colima: --vz-rosetta; Docker Desktop: Settings > General). See README."
fi

# The operator installs its CRDs when it starts; wait until the API server serves them.
log "Waiting for the ApiV4Definition CRD"
retry 30 2 kubectl get crd apiv4definitions.gravitee.io >/dev/null 2>&1 \
  || die "CRD apiv4definitions.gravitee.io never appeared"
kubectl wait --for=condition=Established crd/apiv4definitions.gravitee.io --timeout=60s

# --- 6. Gravitee APIM gateway (DB-less) ------------------------------------
log "Installing Gravitee APIM gateway $APIM_CHART_VERSION (DB-less)"
helm upgrade --install apim apim \
  --repo "$GRAVITEE_HELM_REPO" --version "$APIM_CHART_VERSION" \
  --namespace gravitee \
  --values "$ROOT_DIR/helm/apim-values.yaml" \
  --set-string gateway.services.core.http.authentication.password="$TECHAPI_PASSWORD" \
  --wait --timeout 10m

# --- 7. Backend -------------------------------------------------------------
log "Deploying pong backend"
kubectl apply -f "$ROOT_DIR/k8s/backend/"
kubectl -n pong rollout status deployment/pong --timeout=120s

# --- 8. API definition + gateway network policies --------------------------
# Retried: the operator's admission webhook can need a few seconds after install.
log "Applying /ping API definition"
retry 10 3 kubectl apply -f "$ROOT_DIR/k8s/gravitee/" \
  || die "could not apply k8s/gravitee (is the GKO webhook healthy?)"

# --- 9. Verify --------------------------------------------------------------
"$ROOT_DIR/scripts/test.sh"

log "Done. Try: curl ${GATEWAY_URL}/ping"
