#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
export OBSY_APPS_CONFIG_FILE="${OBSY_APPS_CONFIG_FILE:-/etc/obsy/apps.json}"
export DOCKER_GID="${DOCKER_GID:-$(stat -c '%g' /var/run/docker.sock)}"
export OBSY_PROJECT_NAME="${OBSY_PROJECT_NAME:-obsy}"
export OBSY_BIND_ADDRESS="${OBSY_BIND_ADDRESS:-127.0.0.1}"
export OBSY_HOST_PORT="${OBSY_HOST_PORT:-3001}"
require_file "$OBSY_APPS_CONFIG_FILE"
ensure_expense_network
# Use the upstream service definition, replacing only its published host port.
docker compose --project-name "$OBSY_PROJECT_NAME" --project-directory "$APP_DIR" \
  -f "$APP_DIR/docker-compose.yml" -f "$ORCHESTRATOR_DIR/deploy/compose/obsy.yml" \
  up --build --detach --wait --wait-timeout 180
wait_http "http://127.0.0.1:$OBSY_HOST_PORT/api/metrics"
