#!/usr/bin/env bash
# @mbf-module: exec
# @mbf-rank: ••••
# mbf:requires log
# ==============================================================================
# mbf core library: exec
# Safe array-based command runner, retries, EXIT traps, temp files & locks
# Never calls `exit` inside library functions; returns exit code to caller.
# ==============================================================================

# mbf:state_start
MBF_EXIT_HOOKS=()
MBF_EXIT_TRAP_INSTALLED=0
MBF_LOCK_DIR="${MBF_LOCK_DIR:-${TMPDIR:-/tmp}}"
MBF_STATE_FILE="${MBF_STATE_FILE:-${TMPDIR:-/tmp}/mbf.steps.state}"
# mbf:state_end

# Pre-authenticate sudo session using `sudo -v`
function mbf::exec::init_sudo() {
    if [ "$(id -u)" != "0" ] && command -v sudo >/dev/null 2>&1; then
        sudo -v
    fi
}

# Execute a command safely as an argument array (no `eval`), respecting MBF_DRYRUN=1
# Usage: mbf::exec::run cmd arg1 arg2 ...
function mbf::exec::run() {
    if [ $# -eq 0 ]; then
        return 0
    fi

    mbf::log::info "Executing: $*"
    if mbf::is_dryrun; then
        return 0
    fi

    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        mbf::log::error "Command failed (exit $status): $*"
        return $status
    fi
    return 0
}

# Execute a command with sudo privileges (when non-root and sudo is available)
# Usage: mbf::exec::sudo cmd arg1 arg2 ...
function mbf::exec::sudo() {
    if [ "$(id -u)" == "0" ] || ! command -v sudo >/dev/null 2>&1; then
        mbf::exec::run "$@"
    else
        mbf::exec::run sudo "$@"
    fi
}

# Execute a command as a specific user via sudo
# Usage: mbf::exec::as_user <username> cmd arg1 ...
function mbf::exec::as_user() {
    local user="$1"
    shift
    mbf::exec::run sudo -H -u "$user" -- "$@"
}

# Retry a command up to N attempts with a delay (in seconds) between failures
# Usage: mbf::exec::retry <attempts> <delay_sec> cmd arg1 ...
function mbf::exec::retry() {
    local attempts="$1"
    local delay="$2"
    shift 2
    local count=1

    while [ "$count" -le "$attempts" ]; do
        if mbf::exec::run "$@"; then
            return 0
        fi
        if [ "$count" -lt "$attempts" ]; then
            mbf::log::warn "Attempt $count/$attempts failed. Retrying in ${delay}s..."
            sleep "$delay"
        fi
        count=$((count + 1))
    done

    mbf::log::error "Command failed after $attempts attempts: $*"
    return 1
}

# Run all scripts matching extension in a directory with the given interpreter
# Usage: mbf::exec::scripts_in_dir /path/to/dir bash sh
function mbf::exec::scripts_in_dir() {
    local dir="$1"
    local interpreter="$2"
    local ext="${3:-sh}"

    if [ ! -d "$dir" ]; then
        mbf::log::warn "Directory not found: $dir"
        return 1
    fi

    local file rc=0
    while IFS= read -r -d $'\0' file; do
        mbf::exec::run "$interpreter" "$file" || rc=$?
    done < <(find "$dir" -maxdepth 1 -type f -name "*.$ext" -print0 | sort -z)
    return $rc
}

# Register a cleanup command to run when the current shell exits (preserves prior EXIT trap)
# Usage: mbf::exec::on_exit "rm -f '/tmp/foo'"
function mbf::exec::on_exit() {
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
# Usage: mbf::exec::tmpfile MY_TMP_FILE
function mbf::exec::tmpfile() {
    local out_var="$1"
    local path
    path="$(mktemp "${TMPDIR:-/tmp}/mbf.XXXXXX")" || return 1
    mbf::exec::on_exit "rm -f '$path'"
    printf -v "$out_var" '%s' "$path"
}

# Create a temporary directory, assign its path to `<out_var>`, and auto-delete on exit
# Usage: mbf::exec::tmpdir MY_TMP_DIR
function mbf::exec::tmpdir() {
    local out_var="$1"
    local path
    path="$(mktemp -d "${TMPDIR:-/tmp}/mbf.dir.XXXXXX")" || return 1
    mbf::exec::on_exit "rm -rf '$path'"
    printf -v "$out_var" '%s' "$path"
}

# Acquire a named lock (waits up to timeout_sec; cleans up stale locks from dead PIDs)
# Usage: mbf::exec::lock_acquire "daily_backup" [timeout_sec]
function mbf::exec::lock_acquire() {
    local name="$1"
    local timeout="${2:-0}"
    local lock_path="${MBF_LOCK_DIR}/mbf.${name}.lock"
    local elapsed=0

    mkdir -p "$MBF_LOCK_DIR" 2>/dev/null || true

    while ! mkdir "$lock_path" 2>/dev/null; do
        if [ -f "${lock_path}/pid" ]; then
            local owner_pid
            owner_pid="$(cat "${lock_path}/pid" 2>/dev/null)"
            if [ -n "$owner_pid" ] && ! kill -0 "$owner_pid" 2>/dev/null; then
                rm -rf "$lock_path"
                continue
            fi
        fi

        if [ "$timeout" -le 0 ] || [ "$elapsed" -ge "$timeout" ]; then
            mbf::log::error "Could not acquire lock '$name' ($lock_path)"
            return 1
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    printf '%s\n' "$$" > "${lock_path}/pid"
    mbf::exec::on_exit "rm -rf '$lock_path'"
    return 0
}

# Release a named lock explicitly
function mbf::exec::lock_release() {
    local name="$1"
    rm -rf "${MBF_LOCK_DIR}/mbf.${name}.lock"
}

# Return 0 if step `<step_id>` is recorded as completed in MBF_STATE_FILE
function mbf::exec::step_done() {
    local step_id="$1"
    [ -f "$MBF_STATE_FILE" ] && grep -Fqx "$step_id" "$MBF_STATE_FILE" 2>/dev/null
}

# Mark step `<step_id>` as completed in MBF_STATE_FILE
function mbf::exec::step_mark() {
    local step_id="$1"
    mkdir -p "$(dirname "$MBF_STATE_FILE")" 2>/dev/null || true
    if ! mbf::exec::step_done "$step_id"; then
        printf '%s\n' "$step_id" >> "$MBF_STATE_FILE"
    fi
}

# Run a command/function only if `<step_id>` has not yet completed; marks it done on success
# Usage: mbf::exec::step_run "01_install_nginx" mbf::system::pkg_install nginx
function mbf::exec::step_run() {
    local step_id="$1"
    shift

    if mbf::exec::step_done "$step_id"; then
        mbf::log::info "Skipping completed step: $step_id"
        return 0
    fi

    mbf::log::info "Running step: $step_id"
    if "$@"; then
        mbf::exec::step_mark "$step_id"
        return 0
    fi
    return 1
}
