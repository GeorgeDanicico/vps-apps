#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
git submodule sync --recursive
git submodule update --init --recursive
# Branches are recorded in .gitmodules. Only branch heads, never PR code, deploy.
git submodule update --remote --recursive --checkout
# Stage only the gitlinks, not arbitrary files in the working tree.
while IFS= read -r path; do
  git add -- "$path"
done < <(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' | cut -d ' ' -f 2-)
