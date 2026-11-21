#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# No container. The app's ops/install.sh downloads the native binary its Build workflow made for
# this exact commit (it is never compiled on the VPS), checks it, and installs it with the wrapper
# and the skills.
if [[ ! -f "$APP_DIR/ops/install.sh" ]]; then
  echo "No ops/install.sh in $APP_DIR; nothing to install for this commit."
  exit 0
fi
export LOCKIN_COMMIT="$APP_REVISION"
bash ops/install.sh
