#!/usr/bin/env bash
# gc-picker.sh — author selection dialog (zenity / kdialog / whiptail / dialog / bash select)
# NOTE: no set -euo pipefail here — this file is sourced by other scripts

# Source common library if not already loaded
if [[ -z "${GC_LIB_DIR:-}" ]]; then
    GC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
# shellcheck source=gc-common.sh
[[ "$(type -t gc_config_path)" == "function" ]] || source "$GC_LIB_DIR/gc-common.sh"

# Format author line for display
_gc_format_author() {
    local idx="$1"
    local line="${GC_NAMES[$idx]} <${GC_EMAILS[$idx]}>"
    if [[ -n "${GC_GPGKEYS[$idx]:-}" ]]; then
        line="$line [GPG]"
    fi
    echo "$line"
}

# Show zenity radiolist picker. Returns selected index (0-based) or empty on cancel.
_gc_pick_zenity() {
    local args=()
    args+=(--list --radiolist)
    args+=(--title "git-commitors: Select author")
    args+=(--text "Choose commit author:")
    args+=(--column "" --column "#" --column "Name" --column "Email" --column "GPG")
    args+=(--width 600 --height 400)
    args+=(--hide-column=2)

    local i
    for i in "${!GC_NAMES[@]}"; do
        local gpg_mark=""
        [[ -n "${GC_GPGKEYS[$i]:-}" ]] && gpg_mark="yes"
        local selected="FALSE"
        [[ "$i" -eq 0 ]] && selected="TRUE"
        args+=("$selected" "$i" "${GC_NAMES[$i]}" "${GC_EMAILS[$i]}" "$gpg_mark")
    done

    local result
    result="$(zenity "${args[@]}" 2>/dev/null)" || return 1
    [[ -n "$result" ]] && echo "$result" || return 1
}

# Show kdialog picker
_gc_pick_kdialog() {
    local args=()
    args+=(--menu "Choose commit author:" 0 0 0)

    local i
    for i in "${!GC_NAMES[@]}"; do
        args+=("$i" "$(_gc_format_author "$i")")
    done

    local result
    result="$(kdialog --title "git-commitors" "${args[@]}" 2>/dev/null)" || return 1
    [[ -n "$result" ]] && echo "$result" || return 1
}

# Show whiptail menu picker
_gc_pick_whiptail() {
    local count=${#GC_NAMES[@]}
    local height=$(( count + 8 ))
    [[ $height -gt 24 ]] && height=24

    local args=()
    args+=(--title "git-commitors")
    args+=(--menu "Select commit author:" "$height" 70 "$count")

    local i
    for i in "${!GC_NAMES[@]}"; do
        args+=("$i" "$(_gc_format_author "$i")")
    done

    local result
    result="$(whiptail "${args[@]}" 3>&1 1>&2 2>&3 </dev/tty)" || return 1
    [[ -n "$result" ]] && echo "$result" || return 1
}

# Show dialog menu picker
_gc_pick_dialog() {
    local count=${#GC_NAMES[@]}
    local height=$(( count + 8 ))
    [[ $height -gt 24 ]] && height=24

    local args=()
    args+=(--title "git-commitors")
    args+=(--menu "Select commit author:" "$height" 70 "$count")

    local i
    for i in "${!GC_NAMES[@]}"; do
        args+=("$i" "$(_gc_format_author "$i")")
    done

    local result
    result="$(dialog "${args[@]}" 3>&1 1>&2 2>&3 </dev/tty)" || return 1
    [[ -n "$result" ]] && echo "$result" || return 1
}

# Bash select fallback
_gc_pick_select() {
    local options=()
    local i
    for i in "${!GC_NAMES[@]}"; do
        options+=("$(_gc_format_author "$i")")
    done

    echo "git-commitors: Select commit author:" >/dev/tty
    local PS3="Enter number: "
    local choice
    select choice in "${options[@]}"; do
        if [[ -n "$choice" ]]; then
            echo $(( REPLY - 1 ))
            return 0
        fi
        echo "Invalid selection, try again." >/dev/tty
    done </dev/tty >/dev/tty
    return 1
}

# Main picker function. Returns selected index or empty string on cancel.
gc_pick_author() {
    local display
    display="$(gc_detect_display)"

    local idx=""
    case "$display" in
        gui-zenity)   idx="$(_gc_pick_zenity)" || true ;;
        gui-kdialog)  idx="$(_gc_pick_kdialog)" || true ;;
        tui-whiptail) idx="$(_gc_pick_whiptail)" || true ;;
        tui-dialog)   idx="$(_gc_pick_dialog)" || true ;;
        tui-select)   idx="$(_gc_pick_select)" || true ;;
        none)         return 1 ;;
    esac

    echo "$idx"
}
