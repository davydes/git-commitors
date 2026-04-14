#!/usr/bin/env bash
# git-commitors remote installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/davydes/git-commitors/main/get.sh | bash
#   wget -qO- https://gitlab.com/davydes/git-commitors/-/raw/main/get.sh | bash
#   curl -fsSL https://gitea.example.com/davydes/git-commitors/raw/branch/main/get.sh | bash
#
# Environment:
#   GIT_COMMITORS_REPO  Full clone URL (auto-detected from get.sh URL if possible)
#   GIT_COMMITORS_REF   Branch/tag to checkout (default: main)

set -euo pipefail

REF="${GIT_COMMITORS_REF:-master}"
TMPDIR=""

cleanup() {
    [[ -n "$TMPDIR" && -d "$TMPDIR" ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

# --- Detect clone URL ---

REPO_URL="${GIT_COMMITORS_REPO:-}"

if [[ -z "$REPO_URL" ]]; then
    # Try to detect from parent process (curl/wget) cmdline on Linux
    if [[ -f "/proc/$PPID/cmdline" ]]; then
        cmdline="$(tr '\0' ' ' < "/proc/$PPID/cmdline" 2>/dev/null || true)"
        for token in $cmdline; do
            case "$token" in
                *github.com/*/git-commitors/*)
                    # https://raw.githubusercontent.com/davydes/git-commitors/main/get.sh
                    # -> https://github.com/davydes/git-commitors.git
                    user="$(echo "$token" | sed -n 's|.*github\.com/\([^/]*/git-commitors\).*|\1|p')"
                    [[ -n "$user" ]] && REPO_URL="https://github.com/$user.git"
                    ;;
                *gitlab.com/*/git-commitors/*)
                    user="$(echo "$token" | sed -n 's|.*gitlab\.com/\([^/]*/git-commitors\).*|\1|p')"
                    [[ -n "$user" ]] && REPO_URL="https://gitlab.com/$user.git"
                    ;;
                *git-commitors/raw/branch/*/get.sh)
                    # Gitea: https://host/davydes/git-commitors/raw/branch/main/get.sh
                    base="$(echo "$token" | sed 's|/raw/branch/.*||')"
                    [[ -n "$base" ]] && REPO_URL="$base.git"
                    ;;
            esac
            [[ -n "$REPO_URL" ]] && break
        done
    fi
fi

if [[ -z "$REPO_URL" ]]; then
    # Default repo
    REPO_URL="https://github.com/davydes/git-commitors.git"
fi

# --- Clone and install ---

echo "git-commitors remote installer"
echo "  Repo: $REPO_URL"
echo "  Ref:  $REF"
echo ""

TMPDIR="$(mktemp -d)"

git clone --depth 1 --branch "$REF" "$REPO_URL" "$TMPDIR/git-commitors" 2>&1 | sed 's/^/  /'

echo ""
bash "$TMPDIR/git-commitors/install.sh"
