#!/usr/bin/env bash
# ==============================================================================
# mbf module: exec
# Command execution, sudo management, dry-run, and error logging
# ==============================================================================

function read_sudo_pwd() {
    read -r -s -p "This script requires sudo privileges. [sudo] password for ${USER:-$(id -un)}: " sudo_pwd
    echo ""
    until (printf '%s\n' "$sudo_pwd" | sudo -S echo '' 2>/dev/null); do
        read -r -s -p "Wrong password / Insufficient permission. Try again : " sudo_pwd
        echo ""
    done
}

# Initialize sudo mode
function initialize_sudo() {
    if [ "$(id -u)" != "0" ]; then
        if sudo -n true 2>/dev/null; then
            return 0
        fi
        read_sudo_pwd
    fi
}

# Internal helper: run a shell command string with optional sudo
function _mbf_exec_raw() {
    local command="$1"
    local use_sudo="$2"

    if [ "$use_sudo" == "1" ]; then
        if [ -n "${sudo_pwd:-}" ]; then
            printf '%s\n' "$sudo_pwd" | sudo -S bash -c "$command"
        else
            sudo bash -c "$command"
        fi
    else
        eval "$command"
    fi
}

# Execute command with logging, dry-run, sudo support, and error capture to /tmp/mbf.log
# Supports _sudo_required_ placeholder in command chain
function run_cmd() {
    local command="$*"
    local dryrun="${MBF_DRYRUN:-${I7R_DRYRUN:-0}}"
    local use_sudo="${SUDO_REQUIRED:-0}"

    if [ "$use_sudo" == "1" ]; then
        command="${command//_sudo_required_/sudo}"
        print_with_color "Executing :\nsudo $command"
    else
        command="${command//_sudo_required_ /}"
        command="${command//_sudo_required_/}"
        print_with_color "Executing :\n$command"
    fi

    if [ "$dryrun" == "1" ]; then
        return 0
    fi

    _mbf_exec_raw "$command" "$use_sudo"
    local status=$?

    if [ $status -ne 0 ]; then
        local err_msg="Error (exit $status): $command"
        print_with_color "$err_msg" red >&2
        if function_exists mbf_write_log && { [ "${MBF_LOG:-${I7R_LOGGING:-0}}" == "1" ] || [ "${MBF_DEBUG:-0}" == "1" ]; }; then
            mbf_write_log "ERROR" "$err_msg"
        fi
        if [ "${MBF_DEBUG:-0}" == "1" ] && function_exists mbf_debug_stack_trace; then
            mbf_debug_stack_trace >&2
        fi
        exit $status
    fi
}

# Retry a command up to N times with a delay in seconds
# Usage: run_retry 3 2 curl -fsSL https://example.com
function run_retry() {
    local attempts="$1"
    local delay="$2"
    shift 2
    local cmd="$*"
    local count=1

    while [ "$count" -le "$attempts" ]; do
        if eval "$cmd"; then
            return 0
        fi
        if [ "$count" -lt "$attempts" ]; then
            print_with_color "Attempt $count/$attempts failed. Retrying in ${delay}s..." yellow
            sleep "$delay"
        fi
        count=$((count + 1))
    done

    log_error "Command failed after $attempts attempts: $cmd"
    return 1
}

# Run command as another user (requires SUDO_REQUIRED="1")
function run_cmd_by_user() {
    local user="$1"
    shift
    local command="$*"
    local dryrun="${MBF_DRYRUN:-${I7R_DRYRUN:-0}}"

    if [ "${SUDO_REQUIRED:-0}" == "1" ]; then
        print_with_color "Executing :\nsudo -H -u $user bash -c '$command'"
        if [ "$dryrun" != "1" ]; then
            sudo -H -u "$user" bash -c "$command"
        fi
    fi
}

# Run all executable parts included in a directory
function run_parts_by_dir() {
    local dir="$1"

    if [ -d "$dir" ]; then
        if command -v run-parts >/dev/null 2>&1; then
            run-parts -v "$dir"
        else
            local file
            for file in "$dir"/*; do
                if [ -f "$file" ] && [ -x "$file" ] && [[ "$(basename "$file")" != *.* ]]; then
                    "$file"
                fi
            done
        fi
    fi
}

# Run all scripts with matching extension in a directory using given interpreter
# Usage: run_scripts_by_dir /path/to/scripts bash sh
function run_scripts_by_dir() {
    local dir="$1"
    local interpreter="$2"
    local ext="$3"

    if [ -d "$dir" ]; then
        local file
        while IFS= read -r -d $'\0' file; do
            print_with_color "Executing :\n$interpreter $file"
            "$interpreter" "$file"
        done < <(find "$dir" -maxdepth 1 -type f -name "*.$ext" -print0 | sort -z)
    fi
}

# Execute entry function with parameters
# If MBF_DRYRUN=1 or I7R_DRYRUN=1, only print commands
function execute() {
    local entry="$1"
    shift 1
    local dryrun="${MBF_DRYRUN:-${I7R_DRYRUN:-0}}"

    if [ "$dryrun" == "1" ]; then
        print_with_color "Output command(s) only"
    fi

    if [ $# -eq 0 ] && [ -n "${USAGE:-}" ]; then
        echo "$USAGE"
        return 1
    fi

    "$entry" "$@"
}

# Execute command multiple times
# Usage: run_times 5 0 ls -l
function run_times() {
    local times="$1"
    local sleep_time="$2"
    shift 2
    local command="$*"
    local i

    for ((i = 1; i <= times; i++)); do
        run_cmd "$command"
        if [ "$sleep_time" != "0" ]; then
            sleep "$sleep_time"
        fi
    done
}

# Run command continuously in a loop with sleep interval
# Usage: run_continously 5 date
function run_continously() {
    local sleep_time="$1"
    shift
    local command="$*"

    while true; do
        run_cmd "$command"
        sleep "$sleep_time"
    done
}
