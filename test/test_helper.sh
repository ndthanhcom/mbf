#!/usr/bin/env bash
# ==============================================================================
# mbf Test Helper & Assertion Library (Subshell-Isolated)
# ==============================================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MBF_HOME="$(cd "${TEST_DIR}/.." && pwd)"
export MBF_HOME

MBF_TEST_PASSED=0
MBF_TEST_FAILED=0

function assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-Expected '$expected', but got '$actual'}"

    if [ "$expected" != "$actual" ]; then
        printf '    \033[0;31m[FAIL]\033[0m %s\n' "$msg" >&2
        printf '           expected: [%s]\n' "$expected" >&2
        printf '           actual  : [%s]\n' "$actual" >&2
        exit 1
    fi
}

function assert_ne() {
    local unexpected="$1"
    local actual="$2"
    local msg="${3:-Expected value not equal to '$unexpected'}"

    if [ "$unexpected" == "$actual" ]; then
        printf '    \033[0;31m[FAIL]\033[0m %s\n' "$msg" >&2
        exit 1
    fi
}

function assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-Expected text to contain '$needle'}"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf '    \033[0;31m[FAIL]\033[0m %s\n' "$msg" >&2
        printf '           needle  : [%s]\n' "$needle" >&2
        printf '           haystack: [%s]\n' "$haystack" >&2
        exit 1
    fi
}

function assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-Expected text NOT to contain '$needle'}"

    if [[ "$haystack" == *"$needle"* ]]; then
        printf '    \033[0;31m[FAIL]\033[0m %s\n' "$msg" >&2
        printf '           unexpected needle: [%s]\n' "$needle" >&2
        exit 1
    fi
}

function assert_file_exists() {
    local file="$1"
    local msg="${2:-Expected file '$file' to exist}"

    if [ ! -f "$file" ]; then
        printf '    \033[0;31m[FAIL]\033[0m %s\n' "$msg" >&2
        exit 1
    fi
}

# Run a single test_* function inside an isolated subshell
function run_test_fn() {
    local fn_name="$1"

    (
        if declare -F setup >/dev/null 2>&1; then
            setup
        fi
        if declare -F teardown >/dev/null 2>&1; then
            trap 'teardown' EXIT
        fi
        "$fn_name"
    )
    local rc=$?

    if [ "$rc" -eq 0 ]; then
        printf '  \033[0;32m✓\033[0m %s\n' "$fn_name"
        MBF_TEST_PASSED=$((MBF_TEST_PASSED + 1))
    else
        printf '  \033[0;31m✗\033[0m %s\n' "$fn_name"
        MBF_TEST_FAILED=$((MBF_TEST_FAILED + 1))
    fi
}

# Discover and run all test_* functions defined in the current test script
function run_test_suite() {
    local suite_name="${1:-$(basename "$0")}"
    printf '\n\033[1;36m=== Running suite: %s ===\033[0m\n' "$suite_name"

    local fn
    while IFS= read -r fn; do
        [ -z "$fn" ] && continue
        run_test_fn "$fn"
    done < <(declare -F | awk '{print $3}' | grep '^test_')

    printf 'Suite summary: %d passed, %d failed\n' "$MBF_TEST_PASSED" "$MBF_TEST_FAILED"
    [ "$MBF_TEST_FAILED" -eq 0 ]
}
