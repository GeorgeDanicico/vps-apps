#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
export BRIDGE_ENV_FILE="${BRIDGE_ENV_FILE:-/etc/codex-telegram-bridge/.env.production}"
export SKODA_ENV_FILE="${SKODA_ENV_FILE:-/etc/skoda-mcp-server/.env.production}"
export CODEX_AUTH_DIR="${CODEX_AUTH_DIR:-$HOME/.codex}"
export LOCAL_UID="${LOCAL_UID:-$(id -u)}"
export LOCAL_GID="${LOCAL_GID:-$(id -g)}"
export SKODA_SOURCE_DIR="$VPS_APPS_ROOT/skoda-mcp-server"
export WIKI_SOURCE_DIR="$VPS_APPS_ROOT/llm-wiki"
export SKODA_GATEWAY_TOKEN="${SKODA_GATEWAY_TOKEN:?Set SKODA_GATEWAY_TOKEN in the host bridge config}"
[[ "$SKODA_GATEWAY_TOKEN" != replace-with-a-long-random-value ]] || { echo "Replace the example gateway token in the host config" >&2; exit 1; }
export BRIDGE_PROJECT_NAME="${BRIDGE_PROJECT_NAME:-codex-telegram-bridge}"
require_file "$BRIDGE_ENV_FILE"
require_file "$SKODA_ENV_FILE"
require_file "$CODEX_AUTH_DIR/auth.json"
require_dir "$SKODA_SOURCE_DIR"
require_dir "$WIKI_SOURCE_DIR"
compose=(docker compose --project-name "$BRIDGE_PROJECT_NAME" --project-directory "$APP_DIR" -f "$APP_DIR/compose.yaml" -f "$ORCHESTRATOR_DIR/deploy/compose/bridge.yml")
"${compose[@]}" up --build --detach --wait --wait-timeout 180
# Compose verifies container startup; the gateway additionally needs to serve HTTP.
wait_http http://127.0.0.1:8091/actuator/health
"${compose[@]}" ps
