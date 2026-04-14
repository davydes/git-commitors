#!/usr/bin/env bash
# gc-common.sh — shared library for git-commitors
# NOTE: no set -euo pipefail here — this file is sourced by other scripts

# Arrays for parsed authors
GC_NAMES=()
GC_EMAILS=()
GC_GPGKEYS=()

# Returns path to authors config file
gc_config_path() {
    if [[ -n "${GIT_COMMITORS_CONFIG:-}" ]]; then
        echo "$GIT_COMMITORS_CONFIG"
        return
    fi

    # Primary location
    local primary="$HOME/.git-commitors"
    if [[ -f "$primary" ]]; then
        echo "$primary"
        return
    fi

    # Legacy XDG location (for backward compat)
    local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
    local xdg_path="$xdg/git-commitors/authors.conf"
    if [[ -f "$xdg_path" ]]; then
        echo "$xdg_path"
        return
    fi

    # Default — always in home
    echo "$primary"
}

# Import author from git config
gc_import_git_author() {
    local name email gpgkey
    name="$(git config user.name 2>/dev/null || true)"
    email="$(git config user.email 2>/dev/null || true)"
    gpgkey="$(git config user.signingkey 2>/dev/null || true)"

    if [[ -z "$name" || -z "$email" ]]; then
        return
    fi

    GC_NAMES+=("$name")
    GC_EMAILS+=("$email")
    GC_GPGKEYS+=("$gpgkey")
}

# Parse authors.conf into arrays
gc_parse_authors() {
    GC_NAMES=()
    GC_EMAILS=()
    GC_GPGKEYS=()

    local config
    config="$(gc_config_path)"

    if [[ ! -f "$config" ]]; then
        # No config file — default behavior: import current git user
        gc_import_git_author
        return
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip leading/trailing whitespace
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        # Skip empty lines and comments
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Handle @-directives
        if [[ "$line" == @* ]]; then
            if [[ "$line" == "@git" ]]; then
                gc_import_git_author
            else
                echo "git-commitors: unknown directive '$line' in config (did you mean @git?)" >&2
            fi
            continue
        fi

        # Parse pipe-delimited: Name | Email | GPG Key
        local name email gpgkey
        IFS='|' read -r name email gpgkey <<< "$line"

        name="$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        email="$(echo "$email" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        gpgkey="$(echo "${gpgkey:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        if [[ -z "$name" || -z "$email" ]]; then
            continue
        fi

        GC_NAMES+=("$name")
        GC_EMAILS+=("$email")
        GC_GPGKEYS+=("$gpgkey")
    done < "$config"
}

# Detect available UI: gui-zenity / gui-kdialog / tui-whiptail / tui-dialog / tui-select / none
gc_detect_display() {
    # Manual override
    local override="${GIT_COMMITORS_UI:-}"
    if [[ -n "$override" ]]; then
        case "$override" in
            gui)
                if command -v zenity &>/dev/null; then echo "gui-zenity"; return; fi
                if command -v kdialog &>/dev/null; then echo "gui-kdialog"; return; fi
                echo "none"; return
                ;;
            tui)
                if command -v whiptail &>/dev/null; then echo "tui-whiptail"; return; fi
                if command -v dialog &>/dev/null; then echo "tui-dialog"; return; fi
                if [[ -r /dev/tty ]]; then echo "tui-select"; return; fi
                echo "none"; return
                ;;
            gui-zenity|gui-kdialog|tui-whiptail|tui-dialog|tui-select|none)
                echo "$override"; return
                ;;
        esac
    fi

    # GUI detection
    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
        if command -v zenity &>/dev/null; then echo "gui-zenity"; return; fi
        if command -v kdialog &>/dev/null; then echo "gui-kdialog"; return; fi
    fi

    # TUI detection
    if [[ -r /dev/tty ]]; then
        if command -v whiptail &>/dev/null; then echo "tui-whiptail"; return; fi
        if command -v dialog &>/dev/null; then echo "tui-dialog"; return; fi
        echo "tui-select"; return
    fi

    echo "none"
}

# Check if we're in a rebase
gc_is_rebase() {
    local git_dir
    git_dir="$(git rev-parse --git-dir 2>/dev/null || echo ".git")"

    [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" ]]
}

# Check if interactive mode should be used
gc_is_interactive() {
    # Guard: amending from post-commit hook
    [[ "${GIT_COMMITORS_AMENDING:-}" == "1" ]] && return 1

    # Guard: explicit skip
    [[ "${GIT_COMMITORS_SKIP:-}" == "1" ]] && return 1

    # Guard: CI environments
    [[ -n "${CI:-}" ]] && return 1
    [[ -n "${GITHUB_ACTIONS:-}" ]] && return 1
    [[ -n "${GITLAB_CI:-}" ]] && return 1
    [[ -n "${JENKINS_URL:-}" ]] && return 1
    [[ -n "${TRAVIS:-}" ]] && return 1
    [[ -n "${CIRCLECI:-}" ]] && return 1
    [[ -n "${BUILDKITE:-}" ]] && return 1

    # Guard: rebase
    gc_is_rebase && return 1

    # Guard: no display available
    local display
    display="$(gc_detect_display)"
    [[ "$display" == "none" ]] && return 1

    return 0
}
