BRIDGE_ENV_FILE=/etc/codex-telegram-bridge/.env.production
SKODA_ENV_FILE=/etc/skoda-mcp-server/.env.production
# Set to the host user's existing Codex login directory, readable by LOCAL_UID.
CODEX_AUTH_DIR=/home/r3k1Nu/.codex
LOCAL_UID=1000
LOCAL_GID=1000
# Replace this value on the VPS. It is injected into both bot and gateway.
SKODA_GATEWAY_TOKEN=replace-with-a-long-random-value
# Preserve the project name from `docker compose ls` when adopting an existing stack.
BRIDGE_PROJECT_NAME=codex-telegram-bridge
