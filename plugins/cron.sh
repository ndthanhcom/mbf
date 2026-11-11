#!/usr/bin/env bash
# @mbf-module: cron
# @mbf-rank: ••
# mbf:requires log exec
# ==============================================================================
# mbf plugin: cron
# Idempotent Cron Job Manager (by job ID tag) and Guarded Job Execution Wrapper
# Supports both system crontab command and MBF_CRONTAB_FILE override for testing
# ==============================================================================

function _mbf_cron_read() {
    local user="${1:-}"
    if [ -n "${MBF_CRONTAB_FILE:-}" ]; then
        [ -f "$MBF_CRONTAB_FILE" ] && cat "$MBF_CRONTAB_FILE"
    elif [ -n "$user" ]; then
        crontab -u "$user" -l 2>/dev/null || true
    else
        crontab -l 2>/dev/null || true
    fi
}

function _mbf_cron_write() {
    local user="${1:-}"
    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would update crontab${user:+ for $user}"
        cat >/dev/null
        return 0
    fi
    if [ -n "${MBF_CRONTAB_FILE:-}" ]; then
        cat > "$MBF_CRONTAB_FILE"
    elif [ -n "$user" ]; then
        crontab -u "$user" -
    else
        crontab -
    fi
}

# Add or update a managed cron job identified by `<job_id>`
# Usage: mbf::cron::set <job_id> "<schedule>" "<command>" [user]
function mbf::cron::set() {
    local job_id="$1"
    local schedule="$2"
    local cmd="$3"
    local user="${4:-}"
    local tag="# mbf:id=${job_id}"
    local new_line="${schedule} ${cmd} ${tag}"

    local existing filtered
    existing="$(_mbf_cron_read "$user")"
    filtered="$(printf '%s\n' "$existing" | grep -Fv "$tag" || true)"

    {
        [ -n "$filtered" ] && printf '%s\n' "$filtered"
        printf '%s\n' "$new_line"
    } | _mbf_cron_write "$user"
}

# Remove a managed cron job by `<job_id>`
# Usage: mbf::cron::remove <job_id> [user]
function mbf::cron::remove() {
    local job_id="$1"
    local user="${2:-}"
    local tag="# mbf:id=${job_id}"

    _mbf_cron_read "$user" | grep -Fv "$tag" | _mbf_cron_write "$user"
}

# Disable (comment out) a managed cron job by `<job_id>`
function mbf::cron::disable() {
    local job_id="$1"
    local user="${2:-}"
    local tag="# mbf:id=${job_id}"

    _mbf_cron_read "$user" | sed -E "/${tag}$/ s|^([^#])|#MBF_DISABLED# \1|" | _mbf_cron_write "$user"
}

# Enable (uncomment) a previously disabled managed cron job by `<job_id>`
function mbf::cron::enable() {
    local job_id="$1"
    local user="${2:-}"
    local tag="# mbf:id=${job_id}"

    _mbf_cron_read "$user" | sed -E "/${tag}$/ s|^#MBF_DISABLED# ||" | _mbf_cron_write "$user"
}

# List all mbf-managed cron jobs
function mbf::cron::list() {
    local user="${1:-}"
    _mbf_cron_read "$user" | grep -F "# mbf:id=" || true
}

# Execute a scheduled command guarded by a non-overlapping lock and error logging
# Usage: mbf::cron::run_guarded <job_id> <cmd> [args...]
function mbf::cron::run_guarded() {
    local job_id="$1"
    shift

    mbf::exec::lock_acquire "cron_${job_id}" 0 || return 1
    local start_ts
    start_ts="$(date +%s)"
    mbf::log::info "Cron job '$job_id' started"

    "$@"
    local rc=$?
    local duration=$(( $(date +%s) - start_ts ))
    mbf::exec::lock_release "cron_${job_id}"

    if [ $rc -ne 0 ]; then
        mbf::log::error "Cron job '$job_id' failed (exit $rc) after ${duration}s"
        if declare -F mbf::monitor::alert >/dev/null 2>&1; then
            mbf::monitor::alert "Cron Failed: $job_id" "Command '$*' exited with code $rc" || true
        fi
        return $rc
    fi

    mbf::log::ok "Cron job '$job_id' finished in ${duration}s"
    return 0
}
