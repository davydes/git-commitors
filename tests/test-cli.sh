#!/usr/bin/env bash
# Tests for bin/git-commitors CLI

# --- Version ---

test_cli_version() {
    local result
    result="$(git-commitors version)"
    assert_eq "git-commitors v1.0.0" "$result" "version output"
}
run_test test_cli_version

# --- Help ---

test_cli_help() {
    local result
    result="$(git-commitors help)"
    assert_contains "$result" "Usage:" "help should show usage"
    assert_contains "$result" "init" "help should mention init"
    assert_contains "$result" "remove" "help should mention remove"
    assert_contains "$result" "list" "help should mention list"
    assert_contains "$result" "config" "help should mention config"
}
run_test test_cli_help

# --- Unknown command ---

test_cli_unknown_command() {
    local result
    result="$(git-commitors nonexistent 2>&1)" || true
    assert_contains "$result" "Unknown command" "should report unknown command"
}
run_test test_cli_unknown_command

# --- Init per-repo ---

test_cli_init_repo() {
    local repo
    repo="$(make_test_repo)"
    cd "$repo"

    local result
    result="$(git-commitors init 2>&1)"
    assert_contains "$result" "installed" "should report hooks installed"
    assert_file_exists "$repo/.git/hooks/prepare-commit-msg" "prepare-commit-msg hook installed"
    assert_file_exists "$repo/.git/hooks/post-commit" "post-commit hook installed"

    # Verify hooks are executable
    [[ -x "$repo/.git/hooks/prepare-commit-msg" ]] || { echo "prepare-commit-msg not executable"; return 1; }
    [[ -x "$repo/.git/hooks/post-commit" ]] || { echo "post-commit not executable"; return 1; }

    cd "$PROJECT_DIR"
}
run_test test_cli_init_repo

# --- Init with existing hooks (chaining) ---

test_cli_init_chaining() {
    local repo
    repo="$(make_test_repo)"

    # Create pre-existing hook
    echo '#!/bin/bash' > "$repo/.git/hooks/prepare-commit-msg"
    echo 'echo "original hook"' >> "$repo/.git/hooks/prepare-commit-msg"
    chmod +x "$repo/.git/hooks/prepare-commit-msg"

    cd "$repo"
    local result
    result="$(git-commitors init 2>&1)"

    assert_contains "$result" "chaining" "should report hook chaining"
    assert_file_exists "$repo/.git/hooks/prepare-commit-msg.pre-git-commitors" "backup created"

    # Verify wrapper calls both hooks
    local wrapper_content
    wrapper_content="$(cat "$repo/.git/hooks/prepare-commit-msg")"
    assert_contains "$wrapper_content" "git-commitors" "wrapper references git-commitors"
    assert_contains "$wrapper_content" "pre-git-commitors" "wrapper references original hook"

    cd "$PROJECT_DIR"
}
run_test test_cli_init_chaining

# --- Init idempotent ---

test_cli_init_idempotent() {
    local repo
    repo="$(make_test_repo)"
    cd "$repo"

    git-commitors init >/dev/null 2>&1
    local result
    result="$(git-commitors init 2>&1)"
    assert_contains "$result" "updating" "second init should update"
    assert_file_exists "$repo/.git/hooks/prepare-commit-msg" "hook still exists"

    cd "$PROJECT_DIR"
}
run_test test_cli_init_idempotent

# --- Remove per-repo ---

test_cli_remove_repo() {
    local repo
    repo="$(make_test_repo)"
    cd "$repo"

    git-commitors init >/dev/null 2>&1
    local result
    result="$(git-commitors remove 2>&1)"
    assert_contains "$result" "removed" "should report hooks removed"
    assert_file_not_exists "$repo/.git/hooks/prepare-commit-msg" "prepare-commit-msg removed"
    assert_file_not_exists "$repo/.git/hooks/post-commit" "post-commit removed"

    cd "$PROJECT_DIR"
}
run_test test_cli_remove_repo

# --- Remove restores original hooks ---

test_cli_remove_restores_original() {
    local repo
    repo="$(make_test_repo)"

    # Pre-existing hook
    echo '#!/bin/bash' > "$repo/.git/hooks/post-commit"
    echo 'echo "original"' >> "$repo/.git/hooks/post-commit"
    chmod +x "$repo/.git/hooks/post-commit"

    cd "$repo"
    git-commitors init >/dev/null 2>&1
    git-commitors remove >/dev/null 2>&1

    assert_file_exists "$repo/.git/hooks/post-commit" "original hook restored"
    local content
    content="$(cat "$repo/.git/hooks/post-commit")"
    assert_contains "$content" "original" "restored hook has original content"
    assert_not_contains "$content" "git-commitors" "restored hook has no git-commitors content"

    cd "$PROJECT_DIR"
}
run_test test_cli_remove_restores_original

# --- Remove when not installed ---

test_cli_remove_not_installed() {
    local repo
    repo="$(make_test_repo)"
    cd "$repo"

    local result
    result="$(git-commitors remove 2>&1)"
    assert_contains "$result" "not installed" "should report not installed"

    cd "$PROJECT_DIR"
}
run_test test_cli_remove_not_installed

# --- List ---

test_cli_list_with_authors() {
    local conf
    conf="$(make_test_config "Alice | alice@test.com | KEY123" "Bob | bob@test.com |")"

    local result
    result="$(GIT_COMMITORS_CONFIG="$conf" git-commitors list)"
    assert_contains "$result" "2" "should show count"
    assert_contains "$result" "Alice" "should show Alice"
    assert_contains "$result" "alice@test.com" "should show Alice's email"
    assert_contains "$result" "GPG: KEY123" "should show GPG key"
    assert_contains "$result" "Bob" "should show Bob"
}
run_test test_cli_list_with_authors

test_cli_list_empty() {
    local conf
    conf="$(make_test_config "# empty")"

    local result
    result="$(GIT_COMMITORS_CONFIG="$conf" git-commitors list)"
    assert_contains "$result" "No authors" "should report no authors"
}
run_test test_cli_list_empty

# --- Import ---

test_cli_import() {
    local repo conf_path
    repo="$(make_test_repo)"
    conf_path="$TEST_TMPDIR/import-test.conf"

    cd "$repo"
    local result
    result="$(GIT_COMMITORS_CONFIG="$conf_path" git-commitors import 2>&1)"
    assert_contains "$result" "@git" "should mention @git"
    assert_contains "$result" "Default User" "should show imported name"
    assert_file_exists "$conf_path" "config file created"

    local content
    content="$(cat "$conf_path")"
    assert_contains "$content" "@git" "config should contain @git"

    cd "$PROJECT_DIR"
}
run_test test_cli_import

test_cli_import_idempotent() {
    local repo conf_path
    repo="$(make_test_repo)"
    conf_path="$TEST_TMPDIR/import-idem.conf"
    echo "@git" > "$conf_path"

    cd "$repo"
    local result
    result="$(GIT_COMMITORS_CONFIG="$conf_path" git-commitors import 2>&1)"
    assert_contains "$result" "already present" "should report @git already present"

    cd "$PROJECT_DIR"
}
run_test test_cli_import_idempotent

# --- Init not in git repo ---

test_cli_init_not_git_repo() {
    local tmpdir
    tmpdir="$(mktemp -d "$TEST_TMPDIR/notgit-XXXXXX")"
    cd "$tmpdir"

    local result exit_code
    result="$(git-commitors init 2>&1)" && exit_code=0 || exit_code=$?
    assert_contains "$result" "Not a git" "should report not a git repo"
    [[ $exit_code -ne 0 ]] || { echo "should exit non-zero"; return 1; }

    cd "$PROJECT_DIR"
}
run_test test_cli_init_not_git_repo

# --- Init --global ---

test_cli_init_global() {
    # Save and restore global hooksPath
    local old_hooks_path
    old_hooks_path="$(git config --global core.hooksPath 2>/dev/null || true)"

    local result
    result="$(git-commitors init --global 2>&1)"
    assert_contains "$result" "globally" "should report global install"

    local hooks_path
    hooks_path="$(git config --global core.hooksPath 2>/dev/null || true)"
    assert_contains "$hooks_path" "git-commitors" "global hooksPath should be set"

    # Cleanup
    git-commitors remove --global >/dev/null 2>&1
    if [[ -n "$old_hooks_path" ]]; then
        git config --global core.hooksPath "$old_hooks_path"
    fi
}
run_test test_cli_init_global

# --- Remove --global ---

test_cli_remove_global() {
    git-commitors init --global >/dev/null 2>&1
    local result
    result="$(git-commitors remove --global 2>&1)"
    assert_contains "$result" "unset" "should report unset"

    local hooks_path
    hooks_path="$(git config --global core.hooksPath 2>/dev/null || true)"
    assert_not_contains "$hooks_path" "git-commitors" "global hooksPath should be unset"
}
run_test test_cli_remove_global

# --- Commit wrapper ---

test_cli_commit_single_author() {
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "Wrapper Author | wrapper@test.com")"

    cd "$repo"
    echo "test" > wfile.txt && git add wfile.txt
    GIT_COMMITORS_CONFIG="$conf" git-commitors commit -m "wrapper test" >/dev/null 2>&1

    local author
    author="$(git log -1 --format='%an <%ae>')"
    assert_eq "Wrapper Author <wrapper@test.com>" "$author" "commit wrapper should set author"

    cd "$PROJECT_DIR"
}
run_test test_cli_commit_single_author

test_cli_commit_alias_c() {
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "Alias Author | alias@test.com")"

    cd "$repo"
    echo "test" > afile.txt && git add afile.txt
    GIT_COMMITORS_CONFIG="$conf" git-commitors c -m "alias test" >/dev/null 2>&1

    local author
    author="$(git log -1 --format='%an <%ae>')"
    assert_eq "Alias Author <alias@test.com>" "$author" "'c' alias should work like 'commit'"

    cd "$PROJECT_DIR"
}
run_test test_cli_commit_alias_c

test_cli_commit_no_default_author() {
    # Works even without user.name/user.email
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "Only Author | only@test.com")"

    # Remove default author
    git -C "$repo" config --unset user.name || true
    git -C "$repo" config --unset user.email || true

    cd "$repo"
    echo "test" > nodef.txt && git add nodef.txt
    GIT_COMMITORS_CONFIG="$conf" git-commitors commit -m "no default" >/dev/null 2>&1

    local author committer
    author="$(git log -1 --format='%an <%ae>')"
    committer="$(git log -1 --format='%cn <%ce>')"
    assert_eq "Only Author <only@test.com>" "$author" "author set without default"
    assert_eq "Only Author <only@test.com>" "$committer" "committer set without default"

    cd "$PROJECT_DIR"
}
run_test test_cli_commit_no_default_author

test_cli_commit_no_gpg_sign() {
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "No GPG | nogpg@test.com")"

    cd "$repo"
    echo "test" > nogpg.txt && git add nogpg.txt
    # Even with commit.gpgsign=true, wrapper passes --no-gpg-sign for authors without key
    git config commit.gpgsign false  # ensure no real gpg needed
    GIT_COMMITORS_CONFIG="$conf" git-commitors commit -m "no gpg" >/dev/null 2>&1

    local author
    author="$(git log -1 --format='%an <%ae>')"
    assert_eq "No GPG <nogpg@test.com>" "$author" "author without GPG should work"

    cd "$PROJECT_DIR"
}
run_test test_cli_commit_no_gpg_sign

test_cli_commit_skip() {
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "Skip Author | skip@test.com")"

    cd "$repo"
    echo "test" > skip.txt && git add skip.txt
    GIT_COMMITORS_CONFIG="$conf" GIT_COMMITORS_SKIP=1 git-commitors commit -m "skip" >/dev/null 2>&1

    local author
    author="$(git log -1 --format='%an <%ae>')"
    assert_eq "Default User <default@test.com>" "$author" "SKIP should use default author"

    cd "$PROJECT_DIR"
}
run_test test_cli_commit_skip

test_cli_commit_cancel_no_display() {
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "A | a@test.com" "B | b@test.com")"

    cd "$repo"
    echo "test" > cancel.txt && git add cancel.txt
    local exit_code
    GIT_COMMITORS_CONFIG="$conf" GIT_COMMITORS_UI=none git-commitors commit -m "cancel" >/dev/null 2>&1 && exit_code=0 || exit_code=$?
    [[ $exit_code -ne 0 ]] || { echo "should exit non-zero on cancel"; return 1; }

    cd "$PROJECT_DIR"
}
run_test test_cli_commit_cancel_no_display

test_cli_commit_no_authors() {
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "# empty")"

    cd "$repo"
    echo "test" > empty.txt && git add empty.txt
    local result exit_code
    result="$(GIT_COMMITORS_CONFIG="$conf" git-commitors commit -m "empty" 2>&1)" && exit_code=0 || exit_code=$?
    assert_eq 1 "$exit_code" "should fail with no authors"
    assert_contains "$result" "no authors" "should report no authors"

    cd "$PROJECT_DIR"
}
run_test test_cli_commit_no_authors

test_cli_commit_passes_extra_args() {
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "Args Author | args@test.com")"

    cd "$repo"
    echo "test" > args1.txt
    echo "test2" > args2.txt
    git add args1.txt
    # Use -a to also stage args2.txt
    GIT_COMMITORS_CONFIG="$conf" git-commitors commit -a -m "with extra args" >/dev/null 2>&1

    # args2.txt should be committed via -a
    local tracked
    tracked="$(git ls-files args2.txt)"
    assert_eq "args2.txt" "$tracked" "extra args (-a) should be passed to git commit"

    cd "$PROJECT_DIR"
}
run_test test_cli_commit_passes_extra_args
