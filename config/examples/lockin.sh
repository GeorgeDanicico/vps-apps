# Copy to /etc/vps-apps/lockin.sh; trusted Bash sourced by the adapter. The defaults are in the
# runner account's home; point them at the account that runs Claude if that is a different one.
LOCKIN_PREFIX="$HOME/.local"
LOCKIN_ENV_FILE="$HOME/.config/lockin/env"
LOCKIN_SKILLS_DIR="$HOME/.claude/skills"
