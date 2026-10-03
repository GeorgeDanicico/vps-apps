#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
export DEPLOY_ENV_FILE="${DEPLOY_ENV_FILE:-/etc/expense-tracker/.env.production}"
export IMAGE_NAME="${IMAGE_NAME:-expense-tracker}"
export IMAGE_TAG="$APP_REVISION"
export CONTAINER_NAME="${CONTAINER_NAME:-expense-tracker-web}"
export BIND_ADDRESS="${BIND_ADDRESS:-127.0.0.1}"
export HOST_PORT="${HOST_PORT:-3000}"
require_file "$DEPLOY_ENV_FILE"
ensure_expense_network
bash scripts/deploy.sh
