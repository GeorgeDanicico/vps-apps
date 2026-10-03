#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
export IMAGE="${IMAGE:-api-skoda:$APP_REVISION}"
export CONTAINER_NAME="${CONTAINER_NAME:-api-skoda}"
export HOST_ADDRESS="${HOST_ADDRESS:-127.0.0.1}"
export APP_PORT="${APP_PORT:-8090}"
export MANAGEMENT_PORT="${MANAGEMENT_PORT:-8888}"
# Build the pinned source rather than pulling an unrelated mutable :latest tag.
args=(--build)
if [[ -n "${SKODA_API_ENV_FILE:-}" ]]; then
  require_file "$SKODA_API_ENV_FILE"
  args+=(--env-file "$SKODA_API_ENV_FILE")
fi
bash api-skoda/deploy.sh "${args[@]}"
docker update --restart unless-stopped "$CONTAINER_NAME" >/dev/null
