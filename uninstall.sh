#!/usr/bin/env bash
# git-commitors uninstaller

set -euo pipefail

SHARE_DIR="$HOME/.local/share/git-commitors"
BIN_DIR="$HOME/.local/bin"

echo "Uninstalling git-commitors..."
echo ""

# Remove git alias
current_alias="$(git config --global alias.ci 2>/dev/null || true)"
if [[ "$current_alias" == "commitors commit" ]]; then
    git config --global --unset alias.ci
    echo "  Removed alias: git ci"
elif [[ -n "$current_alias" ]]; then
    echo "  Alias git ci = '$current_alias' (not ours, keeping)"
fi

# Remove global hooks if configured
current_hooks_path="$(git config --global core.hooksPath 2>/dev/null || true)"
if [[ "$current_hooks_path" == *"git-commitors"* ]]; then
    git config --global --unset core.hooksPath
    echo "  Removed global core.hooksPath"
fi

# Remove installed files
if [[ -d "$SHARE_DIR" ]]; then
    rm -rf "$SHARE_DIR"
    echo "  Removed $SHARE_DIR"
fi

if [[ -f "$BIN_DIR/git-commitors" ]]; then
    rm -f "$BIN_DIR/git-commitors"
    echo "  Removed $BIN_DIR/git-commitors"
fi

echo ""
echo "Uninstallation complete."
echo ""
echo "Config files preserved:"
echo "  ~/.git-commitors"
echo ""
echo "Per-repo hooks (if any) must be removed manually:"
echo "  cd /path/to/repo && git commitors remove"
