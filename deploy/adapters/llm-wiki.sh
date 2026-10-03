#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# The orchestrator has already updated the persistent, independent Git checkout.
require_file "$APP_DIR/wiki/index.md"
echo "Wiki updated at $APP_DIR (available to the bridge at /projects/llm-wiki)."
