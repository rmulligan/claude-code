#!/usr/bin/env bash
# Auto-update patched Claude Code CLI when a new version is available.
#
# Checks npm for the latest version, compares with installed version,
# and re-applies patches if newer. Run via systemd timer or cron.
#
# Usage:
#   bash patches/auto-update-patched.sh          # check and update if needed
#   bash patches/auto-update-patched.sh --force  # force re-patch current version

set -euo pipefail

PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/share/claude/patched"
VERSION_FILE="$INSTALL_DIR/.version"
FORCE="${1:-}"

# Get latest version from npm
LATEST="$(npm view @anthropic-ai/claude-code version 2>/dev/null)"
if [[ -z "$LATEST" ]]; then
    echo "[auto-update] Failed to check npm version" >&2
    exit 1
fi

# Get installed version
INSTALLED=""
if [[ -f "$VERSION_FILE" ]]; then
    INSTALLED="$(cat "$VERSION_FILE")"
fi

if [[ "$LATEST" == "$INSTALLED" && "$FORCE" != "--force" ]]; then
    exit 0  # already up to date, silent exit
fi

echo "[auto-update] Updating patched CLI: ${INSTALLED:-none} → ${LATEST}"

# Run the patch script
bash "$PATCH_DIR/apply-local-model-patches.sh" "$LATEST"

# Record version
echo "$LATEST" > "$VERSION_FILE"

echo "[auto-update] Done. Restart inner loop to use new version."
