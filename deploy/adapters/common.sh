#!/usr/bin/env bash
set -Eeuo pipefail
: "${APP_DIR:?}" "${ORCHESTRATOR_DIR:?}" "${VPS_CONFIG_DIR:?}"
# These are trusted, host-owned shell files, never files from an app checkout.
if [[ -f "$VPS_CONFIG_DIR/$APP_NAME.sh" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$VPS_CONFIG_DIR/$APP_NAME.sh"
  set +a
fi
cd "$APP_DIR"
require_file() { [[ -f "$1" ]] || { echo "Required file missing: $1" >&2; exit 1; }; }
require_dir() { [[ -d "$1" ]] || { echo "Required directory missing: $1" >&2; exit 1; }; }
ensure_expense_network() {
  docker network inspect expense-network >/dev/null 2>&1 || docker network create expense-network >/dev/null
}
wait_http() {
  local url="$1" attempt
  for ((attempt=0; attempt<60; attempt++)); do
    if curl --fail --silent --show-error --max-time 3 "$url" >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  echo "Health check failed: $url" >&2
  return 1
}
