#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# Production always runs the JVM image. GraalVM native compilation needs ~3 GB of
# RAM and takes the whole VPS down, so it is never built here.
if [[ -n "${DEPLOY_VARIANT:-}" && "$DEPLOY_VARIANT" != jvm ]]; then
  echo "DEPLOY_VARIANT=$DEPLOY_VARIANT is not supported: native images are not built on the VPS." >&2
  echo "Remove it from $VPS_CONFIG_DIR/$APP_NAME.sh (or set DEPLOY_VARIANT=jvm)." >&2
  exit 1
fi
export DEPLOY_VARIANT=jvm
export IMAGE_NAME="${IMAGE_NAME:-investment:$APP_REVISION}"
export CONTAINER_NAME="${CONTAINER_NAME:-investment}"
export HOST_PORT="${HOST_PORT:-8080}"
command -v curl >/dev/null
ensure_expense_network
# Upstream deploy.sh stops the running container before it builds. Build first so a
# failed or slow build never takes the live service down; upstream's own build step
# then only reuses this image from the Docker cache.
dockerfile="${DOCKERFILE_PATH:-jvm-image/Dockerfile}"
require_file "$dockerfile"
docker build --file "$dockerfile" --tag "$IMAGE_NAME" "$APP_DIR"
bash deploy.sh
