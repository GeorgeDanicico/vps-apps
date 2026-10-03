#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
export DEPLOY_VARIANT="${DEPLOY_VARIANT:-native}"
export IMAGE_NAME="${IMAGE_NAME:-investment:$APP_REVISION}"
export CONTAINER_NAME="${CONTAINER_NAME:-investment}"
export HOST_PORT="${HOST_PORT:-8080}"
command -v curl >/dev/null
ensure_expense_network
bash deploy.sh
