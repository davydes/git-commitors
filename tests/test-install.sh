#!/usr/bin/env bash
# Tests for install.sh, get.sh, and uninstall.sh

# Helper: run install with a mode flag and fake home
_install_with() {
    local fake_home="$1" mode="$2"
    (
        export HOME="$fake_home"
        export PATH="$fake_home/.local/bin:$PATH"
        bash "$PROJECT_DIR/install.sh" "$mode"
    )
}

# --- Core files (all modes) ---

test_install_creates_files() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"

    _install_with "$fake_home" "--alias" >/dev/null 2>&1

    assert_file_exists "$fake_home/.local/share/git-commitors/lib/gc-common.sh" "lib installed"
    assert_file_exists "$fake_home/.local/share/git-commitors/lib/gc-picker.sh" "lib installed"
    assert_file_exists "$fake_home/.local/share/git-commitors/hooks/prepare-commit-msg" "hooks installed"
    assert_file_exists "$fake_home/.local/share/git-commitors/hooks/post-commit" "hooks installed"
    assert_file_exists "$fake_home/.local/bin/git-commitors" "bin installed"
    assert_file_exists "$fake_home/.git-commitors" "config created"

    [[ -x "$fake_home/.local/bin/git-commitors" ]] || { echo "bin not executable"; return 1; }
}
run_test test_install_creates_files

test_install_default_config_has_at_git() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"

    _install_with "$fake_home" "--alias" >/dev/null 2>&1

    local content
    content="$(cat "$fake_home/.git-commitors")"
    assert_contains "$content" "@git" "default config should contain @git"
}
run_test test_install_default_config_has_at_git

test_install_preserves_existing_config() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"
    echo "my custom config" > "$fake_home/.git-commitors"

    _install_with "$fake_home" "--alias" >/dev/null 2>&1

    local content
    content="$(cat "$fake_home/.git-commitors")"
    assert_eq "my custom config" "$content" "existing config preserved"
}
run_test test_install_preserves_existing_config

test_install_preserves_xdg_config() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"
    mkdir -p "$fake_home/.config/git-commitors"
    echo "xdg config" > "$fake_home/.config/git-commitors/authors.conf"

    _install_with "$fake_home" "--alias" >/dev/null 2>&1

    assert_file_not_exists "$fake_home/.git-commitors" "no home config when XDG exists"
}
run_test test_install_preserves_xdg_config

test_install_rejects_wrong_dir() {
    local fake_home tmpdir
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"
    tmpdir="$(mktemp -d "$TEST_TMPDIR/nolib-XXXXXX")"
    cp "$PROJECT_DIR/install.sh" "$tmpdir/"

    local exit_code
    HOME="$fake_home" bash "$tmpdir/install.sh" --alias >/dev/null 2>&1 && exit_code=0 || exit_code=$?
    assert_eq 1 "$exit_code" "should fail without lib/"
}
run_test test_install_rejects_wrong_dir

test_install_rejects_bad_mode() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"

    local exit_code
    _install_with "$fake_home" "--invalid" >/dev/null 2>&1 && exit_code=0 || exit_code=$?
    assert_eq 1 "$exit_code" "should fail with invalid mode"
}
run_test test_install_rejects_bad_mode

# --- Alias mode ---

test_install_alias_sets_alias() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"

    _install_with "$fake_home" "--alias" >/dev/null 2>&1

    local alias_val
    alias_val="$(HOME="$fake_home" git config --global alias.ci 2>/dev/null || true)"
    assert_eq "commitors commit" "$alias_val" "alias mode sets git ci"
}
run_test test_install_alias_sets_alias

test_install_alias_no_global_hook() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"

    _install_with "$fake_home" "--alias" >/dev/null 2>&1

    local hooks_path
    hooks_path="$(HOME="$fake_home" git config --global core.hooksPath 2>/dev/null || true)"
    assert_eq "" "$hooks_path" "alias mode should not set global hooksPath"
}
run_test test_install_alias_no_global_hook

test_install_alias_overwrites_existing() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"
    HOME="$fake_home" git config --global alias.ci "commit --interactive"

    local output
    output="$(_install_with "$fake_home" "--alias" 2>&1)"

    local alias_val
    alias_val="$(HOME="$fake_home" git config --global alias.ci 2>/dev/null || true)"
    assert_eq "commitors commit" "$alias_val" "should overwrite existing alias"
    assert_contains "$output" "overwriting" "should report overwriting"
}
run_test test_install_alias_overwrites_existing

test_install_alias_idempotent() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"

    _install_with "$fake_home" "--alias" >/dev/null 2>&1

    local output
    output="$(_install_with "$fake_home" "--alias" 2>&1)"
    assert_contains "$output" "already set" "should report already set"
}
run_test test_install_alias_idempotent

# --- Hook mode ---

test_install_hook_sets_global_hooks() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"

    _install_with "$fake_home" "--hook" >/dev/null 2>&1

    local hooks_path
    hooks_path="$(HOME="$fake_home" git config --global core.hooksPath 2>/dev/null || true)"
    assert_contains "$hooks_path" "git-commitors" "hook mode sets global hooksPath"
    assert_file_exists "$hooks_path/prepare-commit-msg" "global hook installed"
    assert_file_exists "$hooks_path/post-commit" "global hook installed"
}
run_test test_install_hook_sets_global_hooks

test_install_hook_no_alias() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"

    _install_with "$fake_home" "--hook" >/dev/null 2>&1

    local alias_val
    alias_val="$(HOME="$fake_home" git config --global alias.ci 2>/dev/null || true)"
    assert_eq "" "$alias_val" "hook mode should not set alias"
}
run_test test_install_hook_no_alias

# --- Both mode ---

test_install_both() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"

    _install_with "$fake_home" "--both" >/dev/null 2>&1

    local alias_val
    alias_val="$(HOME="$fake_home" git config --global alias.ci 2>/dev/null || true)"
    assert_eq "commitors commit" "$alias_val" "both mode sets alias"

    local hooks_path
    hooks_path="$(HOME="$fake_home" git config --global core.hooksPath 2>/dev/null || true)"
    assert_contains "$hooks_path" "git-commitors" "both mode sets global hooksPath"
}
run_test test_install_both

# --- get.sh ---

test_get_uses_default_repo() {
    # Without GIT_COMMITORS_REPO, get.sh should default to davydes/git-commitors
    local content
    content="$(cat "$PROJECT_DIR/get.sh")"
    assert_contains "$content" "davydes/git-commitors" "default repo URL should be set"
}
run_test test_get_uses_default_repo

test_get_clones_and_installs() {
    local bare_repo
    bare_repo="$(mktemp -d "$TEST_TMPDIR/bare-XXXXXX")"
    git init --bare "$bare_repo/git-commitors.git" >/dev/null 2>&1

    local tmp_repo
    tmp_repo="$(mktemp -d "$TEST_TMPDIR/tmp-repo-XXXXXX")"
    git init "$tmp_repo" >/dev/null 2>&1
    git -C "$tmp_repo" config user.name "Test" && git -C "$tmp_repo" config user.email "test@test.com"
    cp -r "$PROJECT_DIR"/{lib,hooks,bin,install.sh,get.sh,config} "$tmp_repo/"
    git -C "$tmp_repo" add -A >/dev/null 2>&1
    git -C "$tmp_repo" commit -m "init" >/dev/null 2>&1
    git -C "$tmp_repo" branch -M main >/dev/null 2>&1
    git -C "$tmp_repo" remote add origin "$bare_repo/git-commitors.git"
    git -C "$tmp_repo" push origin main >/dev/null 2>&1

    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"

    (
        export HOME="$fake_home"
        export GIT_COMMITORS_REPO="$bare_repo/git-commitors.git"
        export GIT_COMMITORS_REF="main"
        export GIT_COMMITORS_MODE="--alias"
        bash "$PROJECT_DIR/get.sh"
    ) >/dev/null 2>&1

    assert_file_exists "$fake_home/.local/bin/git-commitors" "CLI installed via get.sh"
    assert_file_exists "$fake_home/.local/share/git-commitors/lib/gc-common.sh" "lib installed via get.sh"
}
run_test test_get_clones_and_installs

# --- Uninstall ---

test_uninstall_removes_alias_mode() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"

    _install_with "$fake_home" "--alias" >/dev/null 2>&1

    (export HOME="$fake_home"; bash "$PROJECT_DIR/uninstall.sh") >/dev/null 2>&1

    local alias_val
    alias_val="$(HOME="$fake_home" git config --global alias.ci 2>/dev/null || true)"
    assert_eq "" "$alias_val" "uninstall removes alias"
    assert_file_not_exists "$fake_home/.local/bin/git-commitors" "bin removed"
    assert_file_exists "$fake_home/.git-commitors" "config preserved"
}
run_test test_uninstall_removes_alias_mode

test_uninstall_removes_hook_mode() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"

    _install_with "$fake_home" "--hook" >/dev/null 2>&1

    (export HOME="$fake_home"; bash "$PROJECT_DIR/uninstall.sh") >/dev/null 2>&1

    local hooks_path
    hooks_path="$(HOME="$fake_home" git config --global core.hooksPath 2>/dev/null || true)"
    assert_eq "" "$hooks_path" "uninstall clears hooksPath"
}
run_test test_uninstall_removes_hook_mode

test_uninstall_removes_both_mode() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"

    _install_with "$fake_home" "--both" >/dev/null 2>&1

    (export HOME="$fake_home"; bash "$PROJECT_DIR/uninstall.sh") >/dev/null 2>&1

    local alias_val hooks_path
    alias_val="$(HOME="$fake_home" git config --global alias.ci 2>/dev/null || true)"
    hooks_path="$(HOME="$fake_home" git config --global core.hooksPath 2>/dev/null || true)"
    assert_eq "" "$alias_val" "alias removed"
    assert_eq "" "$hooks_path" "hooksPath removed"
    assert_file_not_exists "$fake_home/.local/bin/git-commitors" "bin removed"
}
run_test test_uninstall_removes_both_mode

test_uninstall_keeps_foreign_alias() {
    local fake_home
    fake_home="$(mktemp -d "$TEST_TMPDIR/home-XXXXXX")"

    _install_with "$fake_home" "--alias" >/dev/null 2>&1

    # Manually change alias to something else
    HOME="$fake_home" git config --global alias.ci "commit --interactive"

    (export HOME="$fake_home"; bash "$PROJECT_DIR/uninstall.sh") >/dev/null 2>&1

    local alias_val
    alias_val="$(HOME="$fake_home" git config --global alias.ci 2>/dev/null || true)"
    assert_eq "commit --interactive" "$alias_val" "foreign alias preserved"
}
run_test test_uninstall_keeps_foreign_alias
