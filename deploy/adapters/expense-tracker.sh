#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
export DEPLOY_ENV_FILE="${DEPLOY_ENV_FILE:-/etc/expense-tracker/.env.production}"
# The image is built on GitHub and pushed to GHCR (the app's "Build image" workflow); the VPS only
# pulls it, because next build needs more memory than the VPS has.
export IMAGE_SOURCE="${IMAGE_SOURCE:-pull}"
export IMAGE_NAME="${IMAGE_NAME:-ghcr.io/georgedanicico/expense-tracker}"
export IMAGE_TAG="$APP_REVISION"
export CONTAINER_NAME="${CONTAINER_NAME:-expense-tracker-web}"
# The notifications worker: a second container from the same image, started by the app's scripts/deploy.sh.
export WORKER_CONTAINER_NAME="${WORKER_CONTAINER_NAME:-expense-tracker-worker}"
# Written by the worker with its heartbeat.
export GIT_SHA="${GIT_SHA:-$APP_REVISION}"
export BIND_ADDRESS="${BIND_ADDRESS:-127.0.0.1}"
export HOST_PORT="${HOST_PORT:-3000}"
require_file "$DEPLOY_ENV_FILE"
ensure_expense_network
bash scripts/deploy.sh
