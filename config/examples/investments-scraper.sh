# The JVM image is always used; native images are not built on the VPS.
# DEPLOY_VARIANT may be omitted or set to jvm, any other value fails the deployment.
DEPLOY_VARIANT=jvm
CONTAINER_NAME=investment
HOST_PORT=8080
LOG_VOLUME=investment_logs
