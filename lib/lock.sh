#!/usr/bin/env bash
# mbf:requires log fs
# ==============================================================================
# mbf core library: lock
# Process concurrency locks (with stale-PID detection) and idempotent step state
# ==============================================================================

# mbf:state_start
MBF_LOCK_DIR="${MBF_LOCK_DIR:-${TMPDIR:-/tmp}}"
MBF_STATE_FILE="${MBF_STATE_FILE:-${TMPDIR:-/tmp}/mbf.steps.state}"
# mbf:state_end

# Acquire a named lock (waits up to timeout_sec; cleans up stale locks from dead PIDs)
# Usage: mbf::lock::acquire "daily_backup" [timeout_sec]
function mbf::lock::acquire() {
    local name="$1"
    local timeout="${2:-0}"
    local lock_path="${MBF_LOCK_DIR}/mbf.${name}.lock"
    local elapsed=0

    mkdir -p "$MBF_LOCK_DIR" 2>/dev/null || true

    while ! mkdir "$lock_path" 2>/dev/null; do
        # Check if lock owner PID is no longer alive
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
    mbf::fs::on_exit "rm -rf '$lock_path'"
    return 0
}

# Release a named lock explicitly
function mbf::lock::release() {
    local name="$1"
    rm -rf "${MBF_LOCK_DIR}/mbf.${name}.lock"
}

# Return 0 if step `<step_id>` is recorded as completed in MBF_STATE_FILE
function mbf::lock::is_step_done() {
    local step_id="$1"
    [ -f "$MBF_STATE_FILE" ] && grep -Fqx "$step_id" "$MBF_STATE_FILE" 2>/dev/null
}

# Mark step `<step_id>` as completed in MBF_STATE_FILE
function mbf::lock::mark_step() {
    local step_id="$1"
    mkdir -p "$(dirname "$MBF_STATE_FILE")" 2>/dev/null || true
    if ! mbf::lock::is_step_done "$step_id"; then
        printf '%s\n' "$step_id" >> "$MBF_STATE_FILE"
    fi
}

# Run a command/function only if `<step_id>` has not yet completed; marks it done on success
# Usage: mbf::lock::step_run "01_install_nginx" mbf::os::pkg_install nginx
function mbf::lock::step_run() {
    local step_id="$1"
    shift

    if mbf::lock::is_step_done "$step_id"; then
        mbf::log::info "Skipping completed step: $step_id"
        return 0
    fi

    mbf::log::info "Running step: $step_id"
    if "$@"; then
        mbf::lock::mark_step "$step_id"
        return 0
    fi
    return 1
}
