#!/usr/bin/env bash
# git-commitors local installer
# Run from cloned repo: ./install.sh [--alias|--hook|--both]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/lib/gc-common.sh" ]]; then
    echo "Error: run install.sh from the git-commitors source directory." >&2
    echo "For remote install use: curl -fsSL <repo-url>/get.sh | bash" >&2
    exit 1
fi

SHARE_DIR="$HOME/.local/share/git-commitors"
BIN_DIR="$HOME/.local/bin"

# --- Mode selection ---

MODE="${1:-}"

if [[ -z "$MODE" ]]; then
    # Interactive mode selection
    echo "git-commitors — select commit author"
    echo ""
    echo "Choose install mode:"
    echo "  1) alias  — git ci = git commitors commit (recommended)"
    echo "  2) hook   — auto-trigger on every git commit (global hook)"
    echo "  3) both   — alias + global hook"
    echo ""

    if [[ -t 0 ]]; then
        read -rp "Mode [1/2/3] (default: 1): " choice </dev/tty
    else
        choice=""
    fi

    case "${choice:-1}" in
        1|alias)  MODE="--alias" ;;
        2|hook)   MODE="--hook" ;;
        3|both)   MODE="--both" ;;
        *)
            echo "Invalid choice: $choice" >&2
            exit 1
            ;;
    esac
fi

case "$MODE" in
    --alias) install_alias=true;  install_hook=false ;;
    --hook)  install_alias=false; install_hook=true ;;
    --both)  install_alias=true;  install_hook=true ;;
    *)
        echo "Usage: install.sh [--alias|--hook|--both]" >&2
        exit 1
        ;;
esac

echo ""
echo "Installing git-commitors..."
echo ""

# --- Core files (always needed) ---

mkdir -p "$SHARE_DIR/lib"
mkdir -p "$SHARE_DIR/hooks"
mkdir -p "$BIN_DIR"

# Libraries
cp "$SCRIPT_DIR/lib/gc-common.sh" "$SHARE_DIR/lib/"
cp "$SCRIPT_DIR/lib/gc-picker.sh" "$SHARE_DIR/lib/"
echo "  Libraries  -> $SHARE_DIR/lib/"

# Hooks (always copy — needed for both modes and per-repo init)
cp "$SCRIPT_DIR/hooks/prepare-commit-msg" "$SHARE_DIR/hooks/"
cp "$SCRIPT_DIR/hooks/post-commit" "$SHARE_DIR/hooks/"
chmod +x "$SHARE_DIR/hooks/prepare-commit-msg"
chmod +x "$SHARE_DIR/hooks/post-commit"
echo "  Hooks      -> $SHARE_DIR/hooks/"

# CLI
cp "$SCRIPT_DIR/bin/git-commitors" "$BIN_DIR/git-commitors"
chmod +x "$BIN_DIR/git-commitors"
echo "  CLI        -> $BIN_DIR/git-commitors"

# Default config
if [[ ! -f "$HOME/.git-commitors" ]]; then
    xdg="${XDG_CONFIG_HOME:-$HOME/.config}/git-commitors/authors.conf"
    if [[ ! -f "$xdg" ]]; then
        cat > "$HOME/.git-commitors" <<'CONF'
# git-commitors authors config
# Format: Name | Email | GPG Key ID (optional)
# @git imports current user from git config

@git
CONF
        echo "  Config     -> ~/.git-commitors (@git default)"
    fi
fi

# --- Alias mode ---

if $install_alias; then
    current_alias="$(git config --global alias.ci 2>/dev/null || true)"
    if [[ -z "$current_alias" ]]; then
        git config --global alias.ci 'commitors commit'
        echo "  Alias      -> git ci = git commitors commit"
    elif [[ "$current_alias" == "commitors commit" ]]; then
        echo "  Alias      -> git ci (already set)"
    else
        echo "  Alias      -> git ci was '$current_alias', overwriting..."
        git config --global alias.ci 'commitors commit'
        echo "  Alias      -> git ci = git commitors commit"
    fi
fi

# --- Hook mode ---

if $install_hook; then
    global_hooks_dir="$SHARE_DIR/hooks-global"
    mkdir -p "$global_hooks_dir"
    cp "$SHARE_DIR/hooks/prepare-commit-msg" "$global_hooks_dir/"
    cp "$SHARE_DIR/hooks/post-commit" "$global_hooks_dir/"
    chmod +x "$global_hooks_dir/prepare-commit-msg"
    chmod +x "$global_hooks_dir/post-commit"
    git config --global core.hooksPath "$global_hooks_dir"
    echo "  Global hook -> $global_hooks_dir"
fi

# --- Done ---

echo ""
echo "Installation complete!"
echo ""

# Check PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "Warning: $BIN_DIR is not in your PATH."
    echo "Add to your shell profile:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi

if $install_alias; then
    echo "Usage: git ci -m \"message\""
fi
if $install_hook; then
    echo "Usage: git commit -m \"message\"  (hook auto-triggers)"
fi
echo ""
echo "Commands:"
echo "  git commitors config   # edit authors"
echo "  git commitors list     # show authors"
echo "  git commitors import   # add current git user to config"
