#!/usr/bin/env bash
# Smoke test: GET /ping through the gateway must return HTTP 200 with body "pong".
# Retries because the gateway picks up new API definitions a few seconds after apply.
source "$(dirname "$0")/lib.sh"

check_ping() {
  local out status body
  out="$(curl -sS -m 5 -w '\n%{http_code}' "${GATEWAY_URL}/ping" 2>/dev/null)" || return 1
  status="$(printf '%s' "$out" | tail -n 1)"
  body="$(printf '%s' "$out" | sed '$d')"
  [ "$status" = "200" ] && [ "$body" = "pong" ]
}

log "Checking GET ${GATEWAY_URL}/ping"
if retry 30 2 check_ping; then
  log "OK: GET /ping -> 200 pong"
else
  warn "Last response:"
  curl -sS -i -m 5 "${GATEWAY_URL}/ping" >&2 || true
  die "GET /ping did not return 'pong'"
fi
