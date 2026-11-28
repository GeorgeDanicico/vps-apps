#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# Host directory with services.json, alerts.json, secrets.env, obsy.db and backups/. Compose mounts it at /config.
export OBSY_CONFIG_DIR_HOST="${OBSY_CONFIG_DIR_HOST:-$HOME/.config/obsy}"
mkdir -p "$OBSY_CONFIG_DIR_HOST"
chmod 700 "$OBSY_CONFIG_DIR_HOST"
# The container runs as the owner of that directory, so its files stay writable by the deploy user.
export OBSY_UID="${OBSY_UID:-$(id -u)}"
export OBSY_GID="${OBSY_GID:-$(id -g)}"
# Legacy apps.json, read once by Obsy for migration. Mount it only when it exists; otherwise bind an empty list.
export OBSY_APPS_CONFIG_FILE="${OBSY_APPS_CONFIG_FILE:-/etc/obsy/apps.json}"
if [[ ! -f "$OBSY_APPS_CONFIG_FILE" ]]; then
  OBSY_APPS_CONFIG_FILE="$OBSY_CONFIG_DIR_HOST/legacy-apps.json"
  [[ -f "$OBSY_APPS_CONFIG_FILE" ]] || echo '[]' > "$OBSY_APPS_CONFIG_FILE"
fi
export OBSY_APPS_CONFIG_FILE
export DOCKER_GID="${DOCKER_GID:-$(stat -c '%g' /var/run/docker.sock)}"
export OBSY_PROJECT_NAME="${OBSY_PROJECT_NAME:-obsy}"
export OBSY_BIND_ADDRESS="${OBSY_BIND_ADDRESS:-127.0.0.1}"
export OBSY_HOST_PORT="${OBSY_HOST_PORT:-3001}"
ensure_expense_network
# Use the upstream service definition, replacing only its published host port.
docker compose --project-name "$OBSY_PROJECT_NAME" --project-directory "$APP_DIR" \
  -f "$APP_DIR/docker-compose.yml" -f "$ORCHESTRATOR_DIR/deploy/compose/obsy.yml" \
  up --build --detach --wait --wait-timeout 180
wait_http "http://127.0.0.1:$OBSY_HOST_PORT/api/metrics"
