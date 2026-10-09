# The native image is pulled from GHCR (tagged with the deployed commit SHA); nothing
# is built on the VPS.
CONTAINER_NAME=investment
HOST_PORT=8080
LOG_VOLUME=investment_logs
# Needed while the GHCR package is private: a classic PAT with read:packages.
# GHCR_USERNAME=GeorgeDanicico
# GHCR_TOKEN=
# Seconds to wait for upstream to finish publishing a new commit's image.
# IMAGE_PULL_TIMEOUT=1800
