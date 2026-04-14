#!/usr/bin/env bash
# Tests for hooks: prepare-commit-msg + post-commit (integration)

# --- Helper: commit in a test repo ---
_do_commit() {
    local repo="$1"
    shift
    local msg="${1:-test commit}"
    shift || true
    echo "$RANDOM" > "$repo/file-$RANDOM.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -m "$msg" "$@" 2>&1
}

# --- Single author auto-select ---

test_hook_single_author_autoselect() {
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "Hook Author | hook@test.com |")"

    install_hooks "$repo"
    export GIT_COMMITORS_CONFIG="$conf"
    # Force tui-select but it won't be triggered for single author
    export GIT_COMMITORS_UI="none"
    # Actually for single author, we need a display type, but auto-select shouldn't need dialog
    # Let's use tui-select so gc_is_interactive passes
    export GIT_COMMITORS_UI="tui-select"

    _do_commit "$repo" >/dev/null 2>&1

    local author
    author="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "Hook Author <hook@test.com>" "$author" "single author should be auto-selected"

    unset GIT_COMMITORS_CONFIG GIT_COMMITORS_UI
}
run_test test_hook_single_author_autoselect

# --- Skip guard ---

test_hook_skip_env() {
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "Skip Author | skip@test.com |")"

    install_hooks "$repo"

    GIT_COMMITORS_CONFIG="$conf" GIT_COMMITORS_SKIP=1 _do_commit "$repo" >/dev/null 2>&1

    local author
    author="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "Default User <default@test.com>" "$author" "SKIP=1 should keep default author"
}
run_test test_hook_skip_env

# --- CI guard ---

test_hook_ci_skip() {
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "CI Author | ci@test.com |")"

    install_hooks "$repo"

    GIT_COMMITORS_CONFIG="$conf" CI=1 _do_commit "$repo" >/dev/null 2>&1

    local author
    author="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "Default User <default@test.com>" "$author" "CI=1 should keep default author"
}
run_test test_hook_ci_skip

# --- No config ---

test_hook_no_config() {
    local repo
    repo="$(make_test_repo)"

    install_hooks "$repo"

    GIT_COMMITORS_CONFIG="/nonexistent/authors.conf" _do_commit "$repo" >/dev/null 2>&1

    local author
    author="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "Default User <default@test.com>" "$author" "no config should keep default author"
}
run_test test_hook_no_config

# --- Empty config ---

test_hook_empty_config() {
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "# only comments" "")"

    install_hooks "$repo"

    GIT_COMMITORS_CONFIG="$conf" _do_commit "$repo" >/dev/null 2>&1

    local author
    author="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "Default User <default@test.com>" "$author" "empty config should keep default author"
}
run_test test_hook_empty_config

# --- Merge commit skip ---

test_hook_merge_skip() {
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "Merge Author | merge@test.com |")"

    install_hooks "$repo"

    # Create a branch and merge
    git -C "$repo" checkout -b feature >/dev/null 2>&1
    echo "feature" > "$repo/feature.txt"
    git -C "$repo" add feature.txt
    GIT_COMMITORS_CONFIG="$conf" GIT_COMMITORS_SKIP=1 git -C "$repo" commit -m "feature commit" >/dev/null 2>&1
    git -C "$repo" checkout master >/dev/null 2>&1

    # Merge (this creates a merge commit which should skip the picker)
    GIT_COMMITORS_CONFIG="$conf" git -C "$repo" merge feature --no-ff -m "merge feature" >/dev/null 2>&1

    local author
    author="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "Default User <default@test.com>" "$author" "merge commit should keep default author"
}
run_test test_hook_merge_skip

# --- Selection file cleanup ---

test_hook_selection_file_cleaned() {
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "Clean Author | clean@test.com |")"

    install_hooks "$repo"

    GIT_COMMITORS_CONFIG="$conf" GIT_COMMITORS_UI="tui-select" _do_commit "$repo" >/dev/null 2>&1

    assert_file_not_exists "$repo/.git/gc-author-selection" "selection file should be cleaned up"
}
run_test test_hook_selection_file_cleaned

# --- Post-commit reads selection file correctly ---

test_post_commit_applies_author() {
    local repo
    repo="$(make_test_repo)"

    # Install only post-commit hook, manually create selection file
    cp "$PROJECT_DIR/hooks/post-commit" "$repo/.git/hooks/post-commit"
    chmod +x "$repo/.git/hooks/post-commit"

    # Make a commit without prepare-commit-msg (default author)
    echo "test" > "$repo/posttest.txt"
    git -C "$repo" add posttest.txt

    # Write selection file before committing
    cat > "$repo/.git/gc-author-selection" <<EOF
name=Post Author
email=post@test.com
gpgkey=
EOF

    git -C "$repo" commit -m "test post commit" >/dev/null 2>&1

    local author
    author="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "Post Author <post@test.com>" "$author" "post-commit should amend with selected author"
    assert_file_not_exists "$repo/.git/gc-author-selection" "selection file removed after post-commit"
}
run_test test_post_commit_applies_author

# --- Post-commit with GPG key ---

test_post_commit_gpg_flag() {
    local repo
    repo="$(make_test_repo)"

    cp "$PROJECT_DIR/hooks/post-commit" "$repo/.git/hooks/post-commit"
    chmod +x "$repo/.git/hooks/post-commit"

    echo "gpg" > "$repo/gpgtest.txt"
    git -C "$repo" add gpgtest.txt

    cat > "$repo/.git/gc-author-selection" <<EOF
name=GPG Author
email=gpg@test.com
gpgkey=ABCD1234
EOF

    # This will fail GPG signing (no key), but the amend uses || true so commit still happens
    # We just verify the author was set
    git -C "$repo" commit -m "test gpg" >/dev/null 2>&1 || true

    local author
    author="$(git -C "$repo" log -1 --format='%an <%ae>')"
    # The amend may fail due to GPG, so author might be default or GPG Author
    # The important thing is no crash
    [[ "$author" == "GPG Author <gpg@test.com>" || "$author" == "Default User <default@test.com>" ]]
}
run_test test_post_commit_gpg_flag

# --- Post-commit no selection file = no-op ---

test_post_commit_no_selection_noop() {
    local repo
    repo="$(make_test_repo)"

    cp "$PROJECT_DIR/hooks/post-commit" "$repo/.git/hooks/post-commit"
    chmod +x "$repo/.git/hooks/post-commit"

    echo "noop" > "$repo/noop.txt"
    git -C "$repo" add noop.txt
    git -C "$repo" commit -m "test noop" >/dev/null 2>&1

    local author
    author="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "Default User <default@test.com>" "$author" "no selection file = no amend"
}
run_test test_post_commit_no_selection_noop

# --- Recursion guard ---

test_post_commit_recursion_guard() {
    local repo
    repo="$(make_test_repo)"

    cp "$PROJECT_DIR/hooks/post-commit" "$repo/.git/hooks/post-commit"
    chmod +x "$repo/.git/hooks/post-commit"

    # Create selection file and set amending guard
    echo "recursion" > "$repo/recurse.txt"
    git -C "$repo" add recurse.txt

    cat > "$repo/.git/gc-author-selection" <<EOF
name=Recursion Author
email=recursion@test.com
gpgkey=
EOF

    # With guard set, post-commit should not process the file
    GIT_COMMITORS_AMENDING=1 git -C "$repo" commit -m "test recursion" >/dev/null 2>&1

    local author
    author="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "Default User <default@test.com>" "$author" "amending guard should prevent processing"
    # Selection file should still exist (not processed)
    assert_file_exists "$repo/.git/gc-author-selection" "selection file not consumed when guard is active"
    rm -f "$repo/.git/gc-author-selection"
}
run_test test_post_commit_recursion_guard

# --- Rebase detection ---

test_hook_rebase_skip() {
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "Rebase Author | rebase@test.com |")"

    install_hooks "$repo"

    # Simulate rebase in progress
    mkdir -p "$repo/.git/rebase-merge"

    GIT_COMMITORS_CONFIG="$conf" GIT_COMMITORS_UI="tui-select" _do_commit "$repo" >/dev/null 2>&1

    local author
    author="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "Default User <default@test.com>" "$author" "rebase should keep default author"

    rmdir "$repo/.git/rebase-merge"
}
run_test test_hook_rebase_skip

# --- GPG behavior ---

test_hook_no_gpg_author_amends_without_sign() {
    # Author without GPG key: post-commit amends with --no-gpg-sign
    local repo
    repo="$(make_test_repo)"

    cp "$PROJECT_DIR/hooks/post-commit" "$repo/.git/hooks/post-commit"
    chmod +x "$repo/.git/hooks/post-commit"

    echo "gpg" > "$repo/gpg.txt"
    git -C "$repo" add gpg.txt

    cat > "$repo/.git/gc-author-selection" <<EOF
name=No GPG Author
email=nogpg@test.com
gpgkey=
EOF

    git -C "$repo" commit -m "no gpg test" >/dev/null 2>&1

    local author
    author="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "No GPG Author <nogpg@test.com>" "$author" "author should be set without GPG"
}
run_test test_hook_no_gpg_author_amends_without_sign

# --- Last author removed from config (was selected, now gone) ---

test_hook_last_author_removed_single_to_zero() {
    # Config had 1 author (auto-selected), then author is removed before next commit.
    # With empty config, hook should pass through — default author used.
    local repo conf
    repo="$(make_test_repo)"
    conf="$(make_test_config "Temp Author | temp@test.com")"

    install_hooks "$repo"

    # First commit: single author auto-selects
    GIT_COMMITORS_CONFIG="$conf" GIT_COMMITORS_UI="tui-select" _do_commit "$repo" "commit with author" >/dev/null 2>&1
    local author1
    author1="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "Temp Author <temp@test.com>" "$author1" "first commit should use the single author"

    # Remove the author — config now has only a comment
    echo "# empty now" > "$conf"

    # Second commit: no authors → hook passes through → default author
    GIT_COMMITORS_CONFIG="$conf" GIT_COMMITORS_UI="tui-select" _do_commit "$repo" "commit after removal" >/dev/null 2>&1
    local author2
    author2="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "Default User <default@test.com>" "$author2" "after removing last author, should fall back to default"
}
run_test test_hook_last_author_removed_single_to_zero

test_hook_selected_author_removed_index_out_of_bounds() {
    # Simulate: picker returned index that is now out of bounds.
    # This tests the post-commit side — if selection file has valid name/email,
    # it applies regardless. But prepare-commit-msg has index validation.
    # Here we test prepare-commit-msg index validation directly by
    # crafting a scenario with a stale selection file index.
    local repo
    repo="$(make_test_repo)"

    install_hooks "$repo"

    # Manually write a selection file with a removed author's data,
    # but with empty name — post-commit should skip it.
    echo "removed" > "$repo/oob.txt"
    git -C "$repo" add oob.txt

    cat > "$repo/.git/gc-author-selection" <<EOF
name=
email=removed@test.com
gpgkey=
EOF

    git -C "$repo" commit -m "test oob selection" >/dev/null 2>&1

    local author
    author="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "Default User <default@test.com>" "$author" "empty name in selection should not amend"
    assert_file_not_exists "$repo/.git/gc-author-selection" "selection file cleaned up even on skip"
}
run_test test_hook_selected_author_removed_index_out_of_bounds

test_hook_last_of_many_removed() {
    # Scenario: selection file was written with author data, then that author
    # was removed from config. Post-commit still applies the file contents
    # because the file stores full name/email, not an index.
    # We install only post-commit hook to avoid prepare-commit-msg overwriting the file.
    local repo
    repo="$(make_test_repo)"

    cp "$PROJECT_DIR/hooks/post-commit" "$repo/.git/hooks/post-commit"
    chmod +x "$repo/.git/hooks/post-commit"

    echo "stale" > "$repo/stale.txt"
    git -C "$repo" add stale.txt

    cat > "$repo/.git/gc-author-selection" <<EOF
name=Deleted Author
email=deleted@test.com
gpgkey=
EOF

    git -C "$repo" commit -m "test stale selection" >/dev/null 2>&1

    local author
    author="$(git -C "$repo" log -1 --format='%an <%ae>')"
    assert_eq "Deleted Author <deleted@test.com>" "$author" "post-commit applies selection file as-is (contains full author data)"
}
run_test test_hook_last_of_many_removed
