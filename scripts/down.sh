#!/usr/bin/env bash
# Remove everything `up.sh` created: the kind cluster (and every workload in it),
# the project-local kubeconfig and the generated secret.
source "$(dirname "$0")/lib.sh"

log "Deleting kind cluster '$CLUSTER_NAME'"
kind delete cluster --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG"

rm -rf "$ROOT_DIR/.kube" "$SECRETS_DIR"
log "Done"
