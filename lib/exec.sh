#!/usr/bin/env bash
# @mbf-module: exec
# mbf:requires log
# ==============================================================================
# mbf core library: exec
# Safe array-based command runner, retries, EXIT traps, temp files & locks
# Never calls `exit` inside library functions; returns exit code to caller.
#
# Strict-mode note: commands are run as `"$@" || status=$?` so that, even under
# `set -e`, mbf can log the failure and return the status instead of the shell
# aborting before the error message is printed.
# ==============================================================================

# mbf:state_start
MBF_EXIT_HOOKS=()
MBF_EXIT_TRAP_PID=""
_MBF_EXIT_HOOKS_RAN=0
MBF_LOCK_DIR="${MBF_LOCK_DIR:-${MBF_RUNTIME_DIR:-${TMPDIR:-/tmp}/mbf-${UID:-0}}/locks}"
MBF_STATE_FILE="${MBF_STATE_FILE:-${MBF_RUNTIME_DIR:-${TMPDIR:-/tmp}/mbf-${UID:-0}}/steps.state}"
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

    local status=0
    "$@" || status=$?
    if [ "$status" -ne 0 ]; then
        mbf::log::error "Command failed (exit $status): $*"
    fi
    return "$status"
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

# Retry a command up to N attempts with a delay (in seconds) between failures.
# Set `MBF_RETRY_BACKOFF=exp` for exponential backoff (capped at `MBF_RETRY_MAX_DELAY`, default 60s).
# Usage: mbf::exec::retry <attempts> <delay_sec> cmd arg1 ...
function mbf::exec::retry() {
    local attempts="$1"
    local delay="$2"
    shift 2
    local count=1 cur_delay="$delay"
    local max_delay="${MBF_RETRY_MAX_DELAY:-60}"

    while [ "$count" -le "$attempts" ]; do
        if mbf::exec::run "$@"; then
            return 0
        fi
        if [ "$count" -lt "$attempts" ]; then
            mbf::log::warn "Attempt $count/$attempts failed. Retrying in ${cur_delay}s..."
            sleep "$cur_delay"
            if [ "${MBF_RETRY_BACKOFF:-linear}" == "exp" ] && [ "$cur_delay" -gt 0 ]; then
                cur_delay=$((cur_delay * 2))
                [ "$cur_delay" -gt "$max_delay" ] && cur_delay="$max_delay"
            fi
        fi
        count=$((count + 1))
    done

    mbf::log::error "Command failed after $attempts attempts: $*"
    return 1
}

# Run a command with a maximum timeout in seconds (portable: uses `timeout`/`gtimeout` or Bash watchdog).
# Returns 124 on timeout. Respects `MBF_DRYRUN=1`.
# Usage: mbf::exec::timeout <seconds> cmd arg1 ...
function mbf::exec::timeout() {
    local secs="${1:-}"
    shift 1 2>/dev/null || true
    if [ -z "$secs" ] || [ $# -eq 0 ]; then
        mbf::log::error "mbf::exec::timeout: <seconds> and <command> are required"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would run with ${secs}s timeout: $*"
        return 0
    fi

    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
        return $?
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$secs" "$@"
        return $?
    fi

    # Pure-Bash portable watchdog fallback (used on macOS when `timeout`/`gtimeout` is absent).
    # Redirects stdio to /dev/null so the watchdog never holds a caller's `$(...)` pipe open,
    # and traps TERM to terminate its child `sleep` immediately when the command finishes early.
    "$@" &
    local cmd_pid=$!
    (
        sleep "$secs" &
        spid=$!
        trap 'kill "$spid" 2>/dev/null || true; exit 0' TERM
        wait "$spid" 2>/dev/null || true
        kill -TERM "$cmd_pid" 2>/dev/null || true
    ) >/dev/null 2>&1 </dev/null &
    local wd_pid=$!

    local rc=0
    wait "$cmd_pid" 2>/dev/null || rc=$?
    if ! kill -0 "$wd_pid" 2>/dev/null; then
        # Watchdog already fired -> command timed out
        wait "$wd_pid" 2>/dev/null || true
        return 124
    fi
    kill "$wd_pid" 2>/dev/null || true
    wait "$wd_pid" 2>/dev/null || true
    return "$rc"
}

# CI-aware interactive confirmation prompt.
# Returns 0 on yes, 1 on no. Auto-accepts when `MBF_YES=1`; uses `[default:n|y]` when non-interactive or `CI=1`.
# Usage: mbf::exec::confirm "Deploy to production?" [n|y]
function mbf::exec::confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"

    if [ "${MBF_YES:-0}" == "1" ]; then
        return 0
    fi
    if [ -n "${CI:-}" ] || [ ! -t 0 ]; then
        [ "${default,,}" == "y" ]
        return $?
    fi

    local hint="[y/N]" answer=""
    [ "${default,,}" == "y" ] && hint="[Y/n]"
    printf '%s %s ' "$prompt" "$hint" >&2
    IFS= read -r answer || true
    answer="${answer:-$default}"
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# Run all scripts matching extension in a directory with the given interpreter (sorted order)
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
    while IFS= read -r -d '' file; do
        [ -n "$file" ] || continue
        mbf::exec::run "$interpreter" "$file" || rc=$?
    done < <(_mbf_find_sorted "$dir" -maxdepth 1 -type f -name "*.$ext")
    return "$rc"
}

# Register a cleanup command to run when the current shell/subshell exits (LIFO order).
# Hooks are stored as strings and `eval`'d at exit, so quote paths inside them
# (e.g. "rm -f '$path'"). A pre-existing EXIT trap is preserved and runs last.
# Usage: mbf::exec::on_exit "rm -f '/tmp/foo'"
function mbf::exec::on_exit() {
    local current_pid="${BASHPID:-$$}"
    # A subshell inherits the parent's hook array but not its trap: start fresh per process
    if [ "${MBF_EXIT_TRAP_PID:-}" != "$current_pid" ]; then
        MBF_EXIT_HOOKS=()
        _MBF_EXIT_HOOKS_RAN=0
        local existing_trap
        existing_trap="$(trap -p EXIT | sed -E "s/^trap -- '(.*)' EXIT$/\1/")"
        if [ -n "$existing_trap" ] && [ "$existing_trap" != "_mbf_run_exit_hooks" ]; then
            MBF_EXIT_HOOKS+=("$existing_trap")
        fi
        trap '_mbf_run_exit_hooks' EXIT
        trap '_mbf_on_signal 130' INT
        trap '_mbf_on_signal 143' TERM
        MBF_EXIT_TRAP_PID="$current_pid"
    fi
    MBF_EXIT_HOOKS+=("$*")
}

function _mbf_on_signal() {
    local sig_rc="${1:-130}"
    _mbf_run_exit_hooks
    exit "$sig_rc"
}

function _mbf_run_exit_hooks() {
    [ "${_MBF_EXIT_HOOKS_RAN:-0}" -eq 1 ] && return 0
    _MBF_EXIT_HOOKS_RAN=1
    local idx
    for ((idx = ${#MBF_EXIT_HOOKS[@]} - 1; idx >= 0; idx--)); do
        eval "${MBF_EXIT_HOOKS[$idx]}" 2>/dev/null || true
    done
}

# Create a temporary file, assign its path to `<out_var>`, and auto-delete on exit
# Usage: mbf::exec::tmpfile MY_TMP_FILE
function mbf::exec::tmpfile() {
    local out_var="$1"
    local path q_path
    path="$(mktemp "${TMPDIR:-/tmp}/mbf.XXXXXX")" || return 1
    printf -v q_path '%q' "$path"
    mbf::exec::on_exit "rm -f ${q_path}"
    printf -v "$out_var" '%s' "$path"
}

# Create a temporary directory, assign its path to `<out_var>`, and auto-delete on exit
# Usage: mbf::exec::tmpdir MY_TMP_DIR
function mbf::exec::tmpdir() {
    local out_var="$1"
    local path q_path
    path="$(mktemp -d "${TMPDIR:-/tmp}/mbf.dir.XXXXXX")" || return 1
    printf -v q_path '%q' "$path"
    mbf::exec::on_exit "rm -rf ${q_path}"
    printf -v "$out_var" '%s' "$path"
}

# Acquire a named lock (waits up to timeout_sec; cleans up stale locks from dead PIDs).
# Uses `mkdir`, which is atomic on every filesystem, instead of `flock` (not on macOS).
# Usage: mbf::exec::lock_acquire "daily_backup" [timeout_sec]
function mbf::exec::lock_acquire() {
    local name="$1"
    local timeout="${2:-0}"
    local lock_path="${MBF_LOCK_DIR}/mbf.${name}.lock"
    local elapsed=0

    if [ ! -d "$MBF_LOCK_DIR" ]; then
        mkdir -p "$MBF_LOCK_DIR" 2>/dev/null || true
        if [ -n "${MBF_RUNTIME_DIR:-}" ] && [[ "$MBF_LOCK_DIR" == "${MBF_RUNTIME_DIR}"* ]]; then
            chmod 700 "$MBF_LOCK_DIR" 2>/dev/null || true
        fi
    fi

    while ! mkdir "$lock_path" 2>/dev/null; do
        if [ -f "${lock_path}/pid" ]; then
            local owner_pid
            owner_pid="$(cat "${lock_path}/pid" 2>/dev/null || true)"
            if [ -n "$owner_pid" ] && ! kill -0 "$owner_pid" 2>/dev/null; then
                mbf::log::warn "Removing stale lock '$name' (dead PID $owner_pid)"
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

    local q_lock_path
    printf '%s\n' "${BASHPID:-$$}" > "${lock_path}/pid"
    printf -v q_lock_path '%q' "$lock_path"
    mbf::exec::on_exit "rm -rf ${q_lock_path}"
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
    local state_dir
    state_dir="$(dirname "$MBF_STATE_FILE")"
    if [ ! -d "$state_dir" ]; then
        mkdir -p "$state_dir" 2>/dev/null || true
        if [ -n "${MBF_RUNTIME_DIR:-}" ] && [[ "$state_dir" == "${MBF_RUNTIME_DIR}"* ]]; then
            chmod 700 "$state_dir" 2>/dev/null || true
        fi
    fi
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
    local status=0
    "$@" || status=$?
    if [ "$status" -eq 0 ]; then
        if mbf::is_dryrun; then
            mbf::log::info "[DRYRUN] Would mark step '$step_id' completed"
        else
            mbf::exec::step_mark "$step_id"
        fi
    fi
    return "$status"
}
