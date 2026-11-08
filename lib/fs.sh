#!/usr/bin/env bash
# ==============================================================================
# mbf core library: fs
# Temporary file/directory management and chained EXIT trap cleanup
# ==============================================================================

# mbf:state_start
MBF_EXIT_HOOKS=()
MBF_EXIT_TRAP_INSTALLED=0
# mbf:state_end

# Register a cleanup command to run when the current shell exits (preserves prior EXIT trap)
# Usage: mbf::fs::on_exit "rm -f '/tmp/foo'"
function mbf::fs::on_exit() {
    if [ "${MBF_EXIT_TRAP_INSTALLED:-0}" -eq 0 ]; then
        local existing_trap
        existing_trap="$(trap -p EXIT | sed -E "s/^trap -- '(.*)' EXIT$/\1/")"
        if [ -n "$existing_trap" ] && [ "$existing_trap" != "_mbf_run_exit_hooks" ]; then
            MBF_EXIT_HOOKS+=("$existing_trap")
        fi
        trap '_mbf_run_exit_hooks' EXIT
        MBF_EXIT_TRAP_INSTALLED=1
    fi
    MBF_EXIT_HOOKS+=("$*")
}

function _mbf_run_exit_hooks() {
    local idx
    for ((idx = ${#MBF_EXIT_HOOKS[@]} - 1; idx >= 0; idx--)); do
        eval "${MBF_EXIT_HOOKS[$idx]}" 2>/dev/null || true
    done
}

# Create a temporary file, assign its path to `<out_var>`, and auto-delete on exit
# Usage: mbf::fs::tmpfile MY_TMP_FILE
function mbf::fs::tmpfile() {
    local out_var="$1"
    local path
    path="$(mktemp "${TMPDIR:-/tmp}/mbf.XXXXXX")" || return 1
    mbf::fs::on_exit "rm -f '$path'"
    printf -v "$out_var" '%s' "$path"
}

# Create a temporary directory, assign its path to `<out_var>`, and auto-delete on exit
# Usage: mbf::fs::tmpdir MY_TMP_DIR
function mbf::fs::tmpdir() {
    local out_var="$1"
    local path
    path="$(mktemp -d "${TMPDIR:-/tmp}/mbf.dir.XXXXXX")" || return 1
    mbf::fs::on_exit "rm -rf '$path'"
    printf -v "$out_var" '%s' "$path"
}
