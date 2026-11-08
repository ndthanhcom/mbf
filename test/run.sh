#!/usr/bin/env bash
# ==============================================================================
# mbf Automated Test Runner
# Usage: bash test/run.sh [filter]
# ==============================================================================

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"

TOTAL_SUITES=0
FAILED_SUITES=0

printf '\033[1;33mmbf Automated Test Runner\033[0m\n'

for test_file in "${TEST_ROOT}"/unit/test_*.sh; do
    if [ -n "$FILTER" ] && [[ "$(basename "$test_file")" != *"$FILTER"* ]]; then
        continue
    fi
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    if ! bash "$test_file"; then
        FAILED_SUITES=$((FAILED_SUITES + 1))
    fi
done

printf '\n==================================================\n'
if [ "$FAILED_SUITES" -eq 0 ]; then
    printf '\033[0;32mALL %d TEST SUITES PASSED!\033[0m\n' "$TOTAL_SUITES"
    exit 0
else
    printf '\033[0;31m%d OF %d TEST SUITES FAILED!\033[0m\n' "$FAILED_SUITES" "$TOTAL_SUITES"
    exit 1
fi
