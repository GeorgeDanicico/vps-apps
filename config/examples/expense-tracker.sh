# Copy to /etc/vps-apps/expense-tracker.sh; trusted Bash sourced by the adapter.
DEPLOY_ENV_FILE=/etc/expense-tracker/.env.production
CONTAINER_NAME=expense-tracker-web
WORKER_CONTAINER_NAME=expense-tracker-worker
# pull (default): use the image GitHub pushed to GHCR. build: build on the VPS instead.
IMAGE_SOURCE=pull
BIND_ADDRESS=127.0.0.1
HOST_PORT=3000
