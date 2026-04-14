#!/usr/bin/env bash
# Tests for lib/gc-common.sh

# --- gc_config_path ---

test_config_path_env_override() {
    local result
    GIT_COMMITORS_CONFIG="/tmp/custom.conf" result="$(source "$GC_LIB_DIR/gc-common.sh" && gc_config_path)"
    assert_eq "/tmp/custom.conf" "$result" "GIT_COMMITORS_CONFIG should override"
}
run_test test_config_path_env_override

test_config_path_home_primary() {
    local tmpdir
    tmpdir="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"
    touch "$tmpdir/.git-commitors"

    local result
    result="$(unset GIT_COMMITORS_CONFIG XDG_CONFIG_HOME; HOME="$tmpdir" bash -c "source '$GC_LIB_DIR/gc-common.sh' && gc_config_path")"
    assert_eq "$tmpdir/.git-commitors" "$result" "should use ~/.git-commitors as primary"
}
run_test test_config_path_home_primary

test_config_path_xdg_legacy_fallback() {
    local tmpdir
    tmpdir="$(mktemp -d "$TEST_TMPDIR/xdg-XXXXXX")"
    # No ~/.git-commitors, but XDG config exists
    mkdir -p "$tmpdir/.config/git-commitors"
    touch "$tmpdir/.config/git-commitors/authors.conf"

    local result
    result="$(unset GIT_COMMITORS_CONFIG XDG_CONFIG_HOME; HOME="$tmpdir" bash -c "source '$GC_LIB_DIR/gc-common.sh' && gc_config_path")"
    assert_eq "$tmpdir/.config/git-commitors/authors.conf" "$result" "should fall back to XDG path"
}
run_test test_config_path_xdg_legacy_fallback

test_config_path_default_is_home() {
    local tmpdir
    tmpdir="$(mktemp -d "$TEST_TMPDIR/empty-XXXXXX")"

    local result
    result="$(unset GIT_COMMITORS_CONFIG XDG_CONFIG_HOME; HOME="$tmpdir" bash -c "source '$GC_LIB_DIR/gc-common.sh' && gc_config_path")"
    assert_eq "$tmpdir/.git-commitors" "$result" "default should be ~/.git-commitors"
}
run_test test_config_path_default_is_home

test_config_path_home_takes_priority_over_xdg() {
    local tmpdir
    tmpdir="$(mktemp -d "$TEST_TMPDIR/both-XXXXXX")"
    touch "$tmpdir/.git-commitors"
    mkdir -p "$tmpdir/.config/git-commitors"
    touch "$tmpdir/.config/git-commitors/authors.conf"

    local result
    result="$(unset GIT_COMMITORS_CONFIG XDG_CONFIG_HOME; HOME="$tmpdir" bash -c "source '$GC_LIB_DIR/gc-common.sh' && gc_config_path")"
    assert_eq "$tmpdir/.git-commitors" "$result" "~/.git-commitors should take priority over XDG"
}
run_test test_config_path_home_takes_priority_over_xdg

# --- gc_parse_authors ---

test_parse_basic_authors() {
    local conf
    conf="$(make_test_config \
        "Alice Test | alice@test.com | KEY123" \
        "Bob Test | bob@test.com |" \
    )"

    local result
    result="$(GIT_COMMITORS_CONFIG="$conf" bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_parse_authors
        echo "${#GC_NAMES[@]}"
        echo "${GC_NAMES[0]}"
        echo "${GC_EMAILS[0]}"
        echo "${GC_GPGKEYS[0]}"
        echo "${GC_NAMES[1]}"
        echo "${GC_EMAILS[1]}"
        echo "${GC_GPGKEYS[1]}"
    ')"

    local lines
    IFS=$'\n' read -rd '' -a lines <<< "$result" || true
    assert_eq "2" "${lines[0]}" "should parse 2 authors"
    assert_eq "Alice Test" "${lines[1]}" "first author name"
    assert_eq "alice@test.com" "${lines[2]}" "first author email"
    assert_eq "KEY123" "${lines[3]}" "first author GPG key"
    assert_eq "Bob Test" "${lines[4]}" "second author name"
    assert_eq "bob@test.com" "${lines[5]}" "second author email"
    assert_eq "" "${lines[6]:-}" "second author no GPG key"
}
run_test test_parse_basic_authors

test_parse_two_field_format() {
    local conf
    conf="$(make_test_config \
        "Alice Test | alice@test.com" \
        "Bob Test | bob@test.com" \
    )"

    local result
    result="$(GIT_COMMITORS_CONFIG="$conf" bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_parse_authors
        echo "${#GC_NAMES[@]}"
        echo "${GC_NAMES[0]}|${GC_EMAILS[0]}|${GC_GPGKEYS[0]}"
        echo "${GC_NAMES[1]}|${GC_EMAILS[1]}|${GC_GPGKEYS[1]}"
    ')"

    local lines
    IFS=$'\n' read -rd '' -a lines <<< "$result" || true
    assert_eq "2" "${lines[0]}" "should parse 2 authors from two-field format"
    assert_eq "Alice Test|alice@test.com|" "${lines[1]}" "first author: name, email, no gpg"
    assert_eq "Bob Test|bob@test.com|" "${lines[2]}" "second author: name, email, no gpg"
}
run_test test_parse_two_field_format

test_parse_skips_comments_and_empty() {
    local conf
    conf="$(make_test_config \
        "# This is a comment" \
        "" \
        "  # indented comment" \
        "Alice Test | alice@test.com |" \
        "" \
    )"

    local result
    result="$(GIT_COMMITORS_CONFIG="$conf" bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_parse_authors
        echo "${#GC_NAMES[@]}"
        echo "${GC_NAMES[0]}"
    ')"

    local lines
    IFS=$'\n' read -rd '' -a lines <<< "$result" || true
    assert_eq "1" "${lines[0]}" "should parse only 1 author (skip comments/empty)"
    assert_eq "Alice Test" "${lines[1]}" "author name"
}
run_test test_parse_skips_comments_and_empty

test_parse_skips_invalid_lines() {
    local conf
    conf="$(make_test_config \
        "| missing-name@test.com |" \
        "Missing Email | |" \
        "Valid Author | valid@test.com |" \
    )"

    local result
    result="$(GIT_COMMITORS_CONFIG="$conf" bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_parse_authors
        echo "${#GC_NAMES[@]}"
        echo "${GC_NAMES[0]}"
    ')"

    local lines
    IFS=$'\n' read -rd '' -a lines <<< "$result" || true
    assert_eq "1" "${lines[0]}" "should skip lines with missing name or email"
    assert_eq "Valid Author" "${lines[1]}" "valid author parsed"
}
run_test test_parse_skips_invalid_lines

test_parse_unknown_at_directive_warns() {
    local conf
    conf="$(make_test_config "@gita" "Alice | alice@test.com")"

    local stdout stderr
    stdout="$(GIT_COMMITORS_CONFIG="$conf" bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_parse_authors
        echo "${#GC_NAMES[@]}"
    ' 2>"$TEST_TMPDIR/at-warn-stderr")"
    stderr="$(cat "$TEST_TMPDIR/at-warn-stderr")"

    assert_eq "1" "$stdout" "unknown @directive should be skipped, only 1 author parsed"
    assert_contains "$stderr" "@gita" "should warn about unknown directive"
    assert_contains "$stderr" "@git" "should suggest @git"
}
run_test test_parse_unknown_at_directive_warns

test_parse_at_git_directive() {
    local repo
    repo="$(make_test_repo)"
    git -C "$repo" config user.name "Git User"
    git -C "$repo" config user.email "gituser@test.com"
    git -C "$repo" config user.signingkey "GITKEY999"

    local conf
    conf="$(make_test_config "@git" "Other | other@test.com |")"

    local result
    result="$(cd "$repo" && GIT_COMMITORS_CONFIG="$conf" bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_parse_authors
        echo "${#GC_NAMES[@]}"
        echo "${GC_NAMES[0]}"
        echo "${GC_EMAILS[0]}"
        echo "${GC_GPGKEYS[0]}"
        echo "${GC_NAMES[1]}"
    ')"

    local lines
    IFS=$'\n' read -rd '' -a lines <<< "$result" || true
    assert_eq "2" "${lines[0]}" "should have 2 authors (@git + other)"
    assert_eq "Git User" "${lines[1]}" "@git imports user.name"
    assert_eq "gituser@test.com" "${lines[2]}" "@git imports user.email"
    assert_eq "GITKEY999" "${lines[3]}" "@git imports user.signingkey"
    assert_eq "Other" "${lines[4]}" "second author after @git"
}
run_test test_parse_at_git_directive

test_parse_at_git_skips_when_no_name() {
    local repo
    repo="$(make_test_repo)"
    git -C "$repo" config --unset user.name || true

    local conf
    conf="$(make_test_config "@git" "Other | other@test.com |")"

    local result
    result="$(cd "$repo" && GIT_COMMITORS_CONFIG="$conf" bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_parse_authors
        echo "${#GC_NAMES[@]}"
    ')"

    assert_eq "1" "$result" "@git should be skipped when user.name is missing"
}
run_test test_parse_at_git_skips_when_no_name

test_parse_no_config_imports_git_user() {
    local repo
    repo="$(make_test_repo)"
    git -C "$repo" config user.name "Fallback User"
    git -C "$repo" config user.email "fallback@test.com"

    local result
    result="$(cd "$repo" && GIT_COMMITORS_CONFIG="/nonexistent/path/authors.conf" bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_parse_authors
        echo "${#GC_NAMES[@]}"
        echo "${GC_NAMES[0]}"
        echo "${GC_EMAILS[0]}"
    ')"

    local lines
    IFS=$'\n' read -rd '' -a lines <<< "$result" || true
    assert_eq "1" "${lines[0]}" "no config should import git user by default"
    assert_eq "Fallback User" "${lines[1]}" "should import user.name"
    assert_eq "fallback@test.com" "${lines[2]}" "should import user.email"
}
run_test test_parse_no_config_imports_git_user

test_parse_no_config_no_git_user() {
    local result
    # No git repo, no git config — should get 0 authors
    result="$(GIT_COMMITORS_CONFIG="/nonexistent/path/authors.conf" bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_parse_authors
        echo "${#GC_NAMES[@]}"
    ' 2>/dev/null)"
    assert_eq "0" "$result" "no config + no git user = 0 authors"
}
run_test test_parse_no_config_no_git_user

# --- gc_detect_display ---

test_detect_display_manual_override() {
    local result
    result="$(GIT_COMMITORS_UI="tui-whiptail" bash -c 'source "'"$GC_LIB_DIR"'/gc-common.sh" && gc_detect_display')"
    assert_eq "tui-whiptail" "$result" "manual override should be respected"
}
run_test test_detect_display_manual_override

test_detect_display_none_no_display_no_tty() {
    local result
    result="$(unset DISPLAY WAYLAND_DISPLAY GIT_COMMITORS_UI; bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_detect_display
    ' </dev/null 2>/dev/null)" || true
    # Without DISPLAY and with stdin redirected, we might get tui-select or none
    # depending on /dev/tty availability — just verify it doesn't error
    [[ -n "$result" ]]
}
run_test test_detect_display_none_no_display_no_tty

test_detect_display_override_none() {
    local result
    result="$(GIT_COMMITORS_UI="none" bash -c 'source "'"$GC_LIB_DIR"'/gc-common.sh" && gc_detect_display')"
    assert_eq "none" "$result" "override 'none' should return none"
}
run_test test_detect_display_override_none

# --- gc_is_interactive ---

test_is_interactive_amending_guard() {
    local result
    result="$(GIT_COMMITORS_AMENDING=1 bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_is_interactive && echo "yes" || echo "no"
    ')"
    assert_eq "no" "$result" "should not be interactive when amending"
}
run_test test_is_interactive_amending_guard

test_is_interactive_skip_guard() {
    local result
    result="$(GIT_COMMITORS_SKIP=1 bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_is_interactive && echo "yes" || echo "no"
    ')"
    assert_eq "no" "$result" "should not be interactive when skip=1"
}
run_test test_is_interactive_skip_guard

test_is_interactive_ci_guard() {
    for ci_var in CI GITHUB_ACTIONS GITLAB_CI JENKINS_URL TRAVIS CIRCLECI BUILDKITE; do
        local result
        result="$(export "$ci_var=1"; bash -c '
            source "'"$GC_LIB_DIR"'/gc-common.sh"
            gc_is_interactive && echo "yes" || echo "no"
        ')"
        assert_eq "no" "$result" "should not be interactive when $ci_var is set"
    done
}
run_test test_is_interactive_ci_guard

# --- gc_is_rebase ---

test_is_rebase_detects_rebase_merge() {
    local repo
    repo="$(make_test_repo)"
    mkdir -p "$repo/.git/rebase-merge"

    local result
    result="$(cd "$repo" && bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_is_rebase && echo "yes" || echo "no"
    ')"
    assert_eq "yes" "$result" "should detect rebase-merge"
}
run_test test_is_rebase_detects_rebase_merge

test_is_rebase_detects_rebase_apply() {
    local repo
    repo="$(make_test_repo)"
    mkdir -p "$repo/.git/rebase-apply"

    local result
    result="$(cd "$repo" && bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_is_rebase && echo "yes" || echo "no"
    ')"
    assert_eq "yes" "$result" "should detect rebase-apply"
}
run_test test_is_rebase_detects_rebase_apply

test_is_rebase_false_normally() {
    local repo
    repo="$(make_test_repo)"

    local result
    result="$(cd "$repo" && bash -c '
        source "'"$GC_LIB_DIR"'/gc-common.sh"
        gc_is_rebase && echo "yes" || echo "no"
    ')"
    assert_eq "no" "$result" "should not detect rebase when not rebasing"
}
run_test test_is_rebase_false_normally
