#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# The orchestrator has already updated the persistent, independent Git checkout.
# It is shared with the Telegram bridge, so nothing below writes into it.
require_file "$APP_DIR/wiki/index.md"
echo "Wiki updated at $APP_DIR."
if [[ ! -f "$APP_DIR/docker-compose.yml" ]]; then
  echo "No docker-compose.yml in $APP_DIR; skipping the study site container."
  exit 0
fi
export LLM_WIKI_PROJECT_NAME="${LLM_WIKI_PROJECT_NAME:-llm-wiki}"
export LLM_WIKI_BIND_ADDRESS="${LLM_WIKI_BIND_ADDRESS:-127.0.0.1}"
export LLM_WIKI_HOST_PORT="${LLM_WIKI_HOST_PORT:-3002}"
export LLM_WIKI_ENV_FILE="${LLM_WIKI_ENV_FILE:-/etc/llm-wiki/study.env}"
export LLM_WIKI_DATA_DIR="${LLM_WIKI_DATA_DIR:-/var/lib/llm-wiki}"
require_file "$LLM_WIKI_ENV_FILE"
require_dir "$LLM_WIKI_DATA_DIR"
# Use the upstream service definition, replacing only host ports and paths.
docker compose --project-name "$LLM_WIKI_PROJECT_NAME" --project-directory "$APP_DIR" \
  -f "$APP_DIR/docker-compose.yml" -f "$ORCHESTRATOR_DIR/deploy/compose/llm-wiki.yml" \
  up --build --detach --wait --wait-timeout 180
wait_http "http://127.0.0.1:$LLM_WIKI_HOST_PORT/api/health"
