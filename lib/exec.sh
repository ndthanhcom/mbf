#!/usr/bin/env bash
# mbf:requires log
# ==============================================================================
# mbf core library: exec
# Safe array-based command execution, sudo helpers, retries, and dry-run support
# Never calls `exit` inside library functions; returns exit code to caller.
# ==============================================================================

# Pre-authenticate sudo session using `sudo -v`
function mbf::exec::init_sudo() {
    if [ "$(id -u)" != "0" ]; then
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

# Execute a command with sudo privileges, respecting MBF_DRYRUN=1
# Usage: mbf::exec::sudo cmd arg1 arg2 ...
function mbf::exec::sudo() {
    if [ "$(id -u)" == "0" ]; then
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
