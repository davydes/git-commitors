#!/usr/bin/env bash
# Minimal test runner for git-commitors

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BOLD='' RESET=''
fi

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAILURES=()

# Shared temp dir for all tests
export TEST_TMPDIR
TEST_TMPDIR="$(mktemp -d)"

# Setup test git environment
export GC_LIB_DIR="$PROJECT_DIR/lib"
export GIT_COMMITORS_LIB="$PROJECT_DIR/lib"
export GIT_COMMITORS_HOOKS="$PROJECT_DIR/hooks"
export PATH="$PROJECT_DIR/bin:$PATH"
export PROJECT_DIR

# Cleanup
cleanup() {
    rm -rf "$TEST_TMPDIR"
}
trap cleanup EXIT

# Create a fresh test repo in a subdir of TEST_TMPDIR
# Usage: repo=$(make_test_repo)
make_test_repo() {
    local repo
    repo="$(mktemp -d "$TEST_TMPDIR/repo-XXXXXX")"
    git init "$repo" >/dev/null 2>&1
    git -C "$repo" config user.name "Default User"
    git -C "$repo" config user.email "default@test.com"
    # Initial commit so we have a branch
    echo "init" > "$repo/init.txt"
    git -C "$repo" add init.txt
    git -C "$repo" commit -m "initial" >/dev/null 2>&1
    echo "$repo"
}

# Create a test config file, returns its path
# Usage: conf=$(make_test_config "line1" "line2" ...)
make_test_config() {
    local conf
    conf="$(mktemp "$TEST_TMPDIR/conf-XXXXXX")"
    for line in "$@"; do
        echo "$line" >> "$conf"
    done
    echo "$conf"
}

# Install hooks into a repo
install_hooks() {
    local repo="$1"
    cp "$PROJECT_DIR/hooks/prepare-commit-msg" "$repo/.git/hooks/"
    cp "$PROJECT_DIR/hooks/post-commit" "$repo/.git/hooks/"
    chmod +x "$repo/.git/hooks/prepare-commit-msg" "$repo/.git/hooks/post-commit"
}

# Test assertion helpers
assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" != "$actual" ]]; then
        echo "  ASSERT FAILED: ${msg:-expected='$expected' actual='$actual'}" >&2
        echo "    expected: '$expected'" >&2
        echo "    actual:   '$actual'" >&2
        return 1
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  ASSERT FAILED: ${msg:-string does not contain '$needle'}" >&2
        echo "    string: '$haystack'" >&2
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  ASSERT FAILED: ${msg:-string should not contain '$needle'}" >&2
        return 1
    fi
}

assert_file_exists() {
    local path="$1" msg="${2:-}"
    if [[ ! -f "$path" ]]; then
        echo "  ASSERT FAILED: ${msg:-file does not exist: $path}" >&2
        return 1
    fi
}

assert_file_not_exists() {
    local path="$1" msg="${2:-}"
    if [[ -f "$path" ]]; then
        echo "  ASSERT FAILED: ${msg:-file should not exist: $path}" >&2
        return 1
    fi
}

# Run a single test function
run_test() {
    local test_name="$1"
    local output
    if output=$("$test_name" 2>&1); then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "  ${GREEN}PASS${RESET} $test_name"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILURES+=("$test_name")
        echo -e "  ${RED}FAIL${RESET} $test_name"
        if [[ -n "$output" ]]; then
            echo "$output" | sed 's/^/    /'
        fi
    fi
}

skip_test() {
    local test_name="$1" reason="${2:-}"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    echo -e "  ${YELLOW}SKIP${RESET} $test_name${reason:+ ($reason)}"
}

# Run all test files or specific ones
main() {
    echo -e "${BOLD}git-commitors test suite${RESET}"
    echo ""

    local test_files=()
    if [[ $# -gt 0 ]]; then
        test_files=("$@")
    else
        for f in "$TESTS_DIR"/test-*.sh; do
            [[ "$(basename "$f")" == "test-runner.sh" ]] && continue
            test_files+=("$f")
        done
    fi

    for test_file in "${test_files[@]}"; do
        echo -e "${BOLD}$(basename "$test_file")${RESET}"
        source "$test_file"
    done

    echo ""
    echo -e "${BOLD}Results:${RESET} ${GREEN}${PASS_COUNT} passed${RESET}, ${RED}${FAIL_COUNT} failed${RESET}, ${YELLOW}${SKIP_COUNT} skipped${RESET}"

    if [[ ${#FAILURES[@]} -gt 0 ]]; then
        echo -e "${RED}Failed tests:${RESET}"
        for f in "${FAILURES[@]}"; do
            echo "  - $f"
        done
        exit 1
    fi
}

# Only run main if this is the entry point (not sourced by a test file)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
