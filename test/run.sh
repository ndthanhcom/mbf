#!/usr/bin/env bash
# ==============================================================================
# mbf Automated Test Runner
# Runs test/unit/test_*.sh and test/plugins/test_*.sh
# Usage: bash test/run.sh [filter]
# ==============================================================================

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MBF_HOME="$(cd "${TEST_ROOT}/.." && pwd)"
FILTER="${1:-}"

TOTAL_SUITES=0
FAILED_SUITES=0

printf '\033[1;33mmbf Automated Test Runner\033[0m\n'

for test_file in "${TEST_ROOT}"/unit/test_*.sh "${TEST_ROOT}"/plugins/test_*.sh; do
    [ -f "$test_file" ] || continue
    if [ -n "$FILTER" ] && [[ "$test_file" != *"$FILTER"* ]]; then
        continue
    fi
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    if ! bash "$test_file"; then
        FAILED_SUITES=$((FAILED_SUITES + 1))
    fi
done

if command -v shellcheck >/dev/null 2>&1 && [ -z "$FILTER" ]; then
    printf '\n\033[1;36m=== Running ShellCheck ===\033[0m\n'
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    if shellcheck -x "${MBF_HOME}/framework.sh" "${MBF_HOME}/bin/mbf" "${MBF_HOME}"/lib/*.sh "${MBF_HOME}"/plugins/*.sh "${MBF_HOME}"/tools/*.sh; then
        printf '  \033[0;32m✓\033[0m shellcheck passed\n'
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
    fi
fi

printf '\n==================================================\n'
if [ "$FAILED_SUITES" -eq 0 ]; then
    printf '\033[0;32mALL %d TEST SUITES PASSED!\033[0m\n' "$TOTAL_SUITES"
    exit 0
else
    printf '\033[0;31m%d OF %d TEST SUITES FAILED!\033[0m\n' "$FAILED_SUITES" "$TOTAL_SUITES"
    exit 1
fi
