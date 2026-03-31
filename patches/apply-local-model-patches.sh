#!/usr/bin/env bash
# Apply local-model patches to Claude Code CLI.
#
# Downloads the npm package, applies patches for local model usage,
# and installs the patched CLI to ~/.local/bin/claude-patched.
#
# Patches:
#   1. Channel gate bypass (tengu_harbor) — allows development channels
#      with local models (no claude.ai auth required)
#   2. Channel auth bypass — removes accessToken requirement for channels
#
# Usage:
#   bash patches/apply-local-model-patches.sh
#   bash patches/apply-local-model-patches.sh 2.1.87  # specific version
#
# To update after upstream release:
#   git fetch upstream && git merge upstream/main
#   bash patches/apply-local-model-patches.sh <new-version>

set -euo pipefail

VERSION="${1:-$(npm view @anthropic-ai/claude-code version)}"
INSTALL_DIR="$HOME/.local/share/claude/patched"
BIN_LINK="$HOME/.local/bin/claude-patched"

echo "Patching Claude Code v${VERSION} for local model usage..."

# Download fresh npm package
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cd "$WORK_DIR"
npm pack "@anthropic-ai/claude-code@${VERSION}" --quiet 2>/dev/null
tar xzf anthropic-ai-claude-code-*.tgz

CLI_JS="package/cli.js"

if [[ ! -f "$CLI_JS" ]]; then
    echo "ERROR: cli.js not found in npm package" >&2
    exit 1
fi

# Verify we're patching the right version
echo "  Package version: $(node -e "console.log(require('./package/package.json').version)")"

# --- Patch 1: Channel feature gate ---
# tengu_harbor is the feature flag for development channels.
# Default is false (disabled). We enable it unconditionally.
BEFORE=$(grep -c 'function Qj6(){return F8("tengu_harbor",!1)}' "$CLI_JS" || true)
if [[ "$BEFORE" -gt 0 ]]; then
    sed -i 's/function Qj6(){return F8("tengu_harbor",!1)}/function Qj6(){return true}/' "$CLI_JS"
    echo "  ✓ Patch 1: Channel gate (tengu_harbor) → always true"
else
    echo "  ⚠ Patch 1: Channel gate pattern not found (may have changed upstream)"
fi

# --- Patch 2: Channel auth bypass ---
# Channels require an accessToken from claude.ai login.
# We bypass this check for local model usage.
BEFORE=$(grep -c 'channels requires claude.ai authen' "$CLI_JS" || true)
if [[ "$BEFORE" -gt 0 ]]; then
    sed -i 's/if(!i7()?.accessToken)return{action:"skip",kind:"auth",reason:"channels requires claude.ai authentication (run \/login)"}/if(false)return{action:"skip",kind:"auth",reason:"channels requires claude.ai authentication"}/' "$CLI_JS"
    echo "  ✓ Patch 2: Channel auth bypass → always passes"
else
    echo "  ⚠ Patch 2: Channel auth pattern not found (may have changed upstream)"
fi

# Install
mkdir -p "$INSTALL_DIR"
cp "$CLI_JS" "$INSTALL_DIR/cli.js"
cp package/package.json "$INSTALL_DIR/package.json"
cp -r package/vendor "$INSTALL_DIR/vendor" 2>/dev/null || true

# Create wrapper script
cat > "$BIN_LINK" << 'WRAPPER'
#!/usr/bin/env bash
# Patched Claude Code CLI — channels enabled for local models.
exec node "$HOME/.local/share/claude/patched/cli.js" "$@"
WRAPPER
chmod +x "$BIN_LINK"

echo ""
echo "Installed patched Claude Code v${VERSION}:"
echo "  CLI:     $INSTALL_DIR/cli.js"
echo "  Binary:  $BIN_LINK"
echo ""
echo "Usage: claude-patched --dangerously-load-development-channels server:matrix"
