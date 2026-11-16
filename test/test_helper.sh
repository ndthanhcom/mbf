#!/usr/bin/env bash
# ==============================================================================
# mbf Test Helper, Command Stub Harness & Assertion Library (Subshell-Isolated)
# Runs every test function in both Standard Mode and Strict Mode (`mbf::strict`).
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

# Create a command stub in MBF_MOCK_BIN that logs its invocation to MBF_MOCK_LOG,
# prints optional `<stdout_text>`, and exits with `<exit_code>` (default: 0).
# Usage: mock_cmd <cmd_name> [exit_code] [stdout_text]
function mock_cmd() {
    local name="$1"
    local rc="${2:-0}"
    local out="${3:-}"
    mkdir -p "$MBF_MOCK_BIN"
    cat <<EOF > "${MBF_MOCK_BIN}/${name}"
#!/usr/bin/env bash
printf '%s %s\n' "${name}" "\$*" >> "${MBF_MOCK_LOG}"
EOF
    if [ -n "$out" ]; then
        printf 'cat <<'\''MBF_MOCK_EOF'\''\n%s\nMBF_MOCK_EOF\n' "$out" >> "${MBF_MOCK_BIN}/${name}"
    fi
    printf 'exit %d\n' "$rc" >> "${MBF_MOCK_BIN}/${name}"
    chmod +x "${MBF_MOCK_BIN}/${name}"
}

# Assert that a stubbed command was invoked with arguments matching `<expected_substr>`
# Usage: assert_called_with <cmd_name> <expected_substr>
function assert_called_with() {
    local name="$1"
    local expected="$2"
    local calls=""
    [ -f "${MBF_MOCK_LOG:-}" ] && calls="$(cat "$MBF_MOCK_LOG")"
    if [[ "$calls" != *"${name} "*"${expected}"* ]] && [[ "$calls" != *"${name}"$'\n'* ]]; then
        printf '    \033[0;31m[FAIL]\033[0m Expected stub "%s" to be called with "%s"\n' "$name" "$expected" >&2
        printf '           recorded calls:\n%s\n' "$calls" >&2
        exit 1
    fi
}

# Run a single test_* function inside an isolated subshell (first standard, then strict mode)
function run_test_fn() {
    local fn_name="$1"
    local mode rc=0

    for mode in standard strict; do
        (
            MBF_MOCK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mbf.mock.XXXXXX")"
            MBF_MOCK_BIN="${MBF_MOCK_DIR}/bin"
            MBF_MOCK_LOG="${MBF_MOCK_DIR}/calls.log"
            mkdir -p "$MBF_MOCK_BIN"
            : > "$MBF_MOCK_LOG"
            export MBF_MOCK_DIR MBF_MOCK_BIN MBF_MOCK_LOG
            export PATH="${MBF_MOCK_BIN}:$PATH"

            if declare -F mbf::exec::on_exit >/dev/null 2>&1; then
                mbf::exec::on_exit "rm -rf '$MBF_MOCK_DIR'"
            else
                trap "rm -rf '$MBF_MOCK_DIR'" EXIT
            fi

            if [ "$mode" == "strict" ] && declare -F mbf::strict >/dev/null 2>&1; then
                mbf::strict
            fi
            if declare -F setup >/dev/null 2>&1; then
                setup
            fi
            "$fn_name"
        ) || { rc=$?; break; }
    done

    if [ "$rc" -eq 0 ]; then
        printf '  \033[0;32m✓\033[0m %s (standard + strict)\n' "$fn_name"
        MBF_TEST_PASSED=$((MBF_TEST_PASSED + 1))
    else
        printf '  \033[0;31m✗\033[0m %s (failed in %s mode)\n' "$fn_name" "$mode"
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
