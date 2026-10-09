#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# Production runs the native image that upstream's "Publish image and notify VPS
# deployments" workflow pushes to GHCR, tagged with the commit SHA. Nothing is compiled
# on the VPS.
export IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-ghcr.io/georgedanicico/investments-scraper}"
export IMAGE_NAME="$IMAGE_REPOSITORY:$APP_REVISION"
export CONTAINER_NAME="${CONTAINER_NAME:-investment}"
export HOST_PORT="${HOST_PORT:-8080}"
export DOCKER_NETWORK=expense-network
command -v curl >/dev/null
ensure_expense_network
# Private packages need a token with read:packages. Without one, an existing
# `docker login ghcr.io` of the runner account is used.
if [[ -n "${GHCR_TOKEN:-}" ]]; then
  printf '%s' "$GHCR_TOKEN" | docker login ghcr.io \
    --username "${GHCR_USERNAME:?GHCR_USERNAME is required with GHCR_TOKEN}" --password-stdin >/dev/null
fi
# The image for a fresh commit may still be building upstream. Pull before
# deploy-ghcr.sh stops the running container, so a missing image never takes the
# live service down; deploy-ghcr.sh's own pull then finds it locally.
pull_timeout="${IMAGE_PULL_TIMEOUT:-1800}"
deadline=$((SECONDS + pull_timeout))
until docker pull --quiet "$IMAGE_NAME" >/dev/null; do
  if ((SECONDS >= deadline)); then
    echo "Image not published within ${pull_timeout}s: $IMAGE_NAME" >&2
    exit 1
  fi
  echo "Waiting for $IMAGE_NAME to be published..."
  sleep 30
done
require_file deploy-ghcr.sh
bash deploy-ghcr.sh
