#!/usr/bin/env bash
# Shared settings for up.sh / down.sh / test.sh. Every version is pinned here.
# Written for bash 3.2 (macOS default) and GNU/Linux alike.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CLUSTER_NAME="gravitee"
# Project-local kubeconfig: we never touch ~/.kube/config or switch the
# user's current context.
export KUBECONFIG="${ROOT_DIR}/.kube/config"

GRAVITEE_HELM_REPO="https://helm.gravitee.io"
GKO_CHART_VERSION="4.12.20"
APIM_CHART_VERSION="4.12.20"

GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:8082}"

SECRETS_DIR="${ROOT_DIR}/.secrets"
TECHAPI_PASSWORD_FILE="${SECRETS_DIR}/gateway-techapi-password"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# retry <attempts> <sleep-seconds> <command...>
retry() {
  local attempts="$1" delay="$2" n=1
  shift 2
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then
      return 1
    fi
    n=$((n + 1))
    sleep "$delay"
  done
}
