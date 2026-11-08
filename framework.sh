#!/usr/bin/env bash
# ==============================================================================
# mbf — Micro Bash Framework
# Core loader, lifecycle hooks, and base utilities
# ==============================================================================

# Avoid loading framework.sh multiple times in the same shell execution
if [ -n "${MBF_CORE_LOADED:-}" ]; then
    return 0 2>/dev/null || true
fi
MBF_CORE_LOADED=1

##########
# Section 0. Framework paths and Environment parameters

MBF_HOME="${MBF_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# Keep DIR for backward compatibility if not already set by caller
DIR="${DIR:-$MBF_HOME}"
PRINTF="${PRINTF:-$(command -v printf)}"
SED="${SED:-$(command -v sed)}"

# Manual of script based on framework.sh (printed when -h/--help or no input param is given to execute)
USAGE="${USAGE:-}"
# Space-separated required external commands
I7R_REQUIREMENTS="${I7R_REQUIREMENTS:-}"
MBF_REQUIREMENTS="${MBF_REQUIREMENTS:-}"

# Track loaded modules to avoid duplicate imports
MBF_LOADED_MODULES="${MBF_LOADED_MODULES:- }"
# Cleanup commands registered via mbf_on_exit
MBF_EXIT_HOOKS=()

# Check if a module is already loaded
function mbf_is_loaded() {
    local mod="$1"
    [[ "$MBF_LOADED_MODULES" == *" ${mod} "* ]]
}

# Load one or more mbf modules with deduplication
# Usage: mbf_use config args
function mbf_use() {
    local lib
    for lib in "$@"; do
        lib="${lib%.sh}"
        local canonical="$lib"
        case "$lib" in
            parameters) canonical="args" ;;
            authenication|authentication) canonical="auth" ;;
        esac

        if mbf_is_loaded "$canonical"; then
            continue
        fi

        if [ -f "${MBF_HOME}/lib/${canonical}.sh" ]; then
            MBF_LOADED_MODULES="${MBF_LOADED_MODULES}${canonical} "
            # shellcheck disable=SC1090
            source "${MBF_HOME}/lib/${canonical}.sh"
        elif [ -f "${MBF_HOME}/${lib}.sh" ]; then
            MBF_LOADED_MODULES="${MBF_LOADED_MODULES}${canonical} "
            # shellcheck disable=SC1090
            source "${MBF_HOME}/${lib}.sh"
        else
            echo "Library $lib not found in ${MBF_HOME}/lib or ${MBF_HOME}" >&2
            return 1
        fi
    done
}

# Backward-compatible alias for mbf_use
function _import() {
    if ! mbf_use "$@"; then
        exit 1
    fi
}

# Enable strict execution mode with informative error trap
function mbf_strict_mode() {
    set -Eeuo pipefail
    trap '_mbf_error_handler "${BASH_SOURCE[0]}" "${LINENO}" "${BASH_COMMAND}" "$?"' ERR
}

function _mbf_error_handler() {
    local src="$1"
    local line="$2"
    local cmd="$3"
    local code="$4"
    local msg="Error in ${src}:${line} — '${cmd}' exited with status ${code}"
    print_with_color "$msg" "red" >&2
    if function_exists mbf_write_log && { [ "${MBF_LOG:-0}" == "1" ] || [ "${MBF_DEBUG:-0}" == "1" ]; }; then
        mbf_write_log "ERROR" "$msg"
    fi
}

# Register a command to run automatically when the script exits
function mbf_on_exit() {
    MBF_EXIT_HOOKS+=("$*")
    trap '_mbf_run_exit_hooks' EXIT
}

function _mbf_run_exit_hooks() {
    local hook
    for hook in "${MBF_EXIT_HOOKS[@]}"; do
        eval "$hook" 2>/dev/null || true
    done
}

# Create a temporary file; if a variable name is passed as $1, assigns path to $1 and registers cleanup on exit
function mbf_mktemp_file() {
    local tmpf
    tmpf="$(mktemp "${TMPDIR:-/tmp}/mbf.XXXXXX")"
    if [ -n "${1:-}" ]; then
        mbf_on_exit "rm -f '$tmpf'"
        printf -v "$1" '%s' "$tmpf"
    else
        printf '%s\n' "$tmpf"
    fi
}

# Create a temporary directory; if a variable name is passed as $1, assigns path to $1 and registers cleanup on exit
function mbf_mktemp_dir() {
    local tmpd
    tmpd="$(mktemp -d "${TMPDIR:-/tmp}/mbf.dir.XXXXXX")"
    if [ -n "${1:-}" ]; then
        mbf_on_exit "rm -rf '$tmpd'"
        printf -v "$1" '%s' "$tmpd"
    else
        printf '%s\n' "$tmpd"
    fi
}

# Get current working directory
function get_pwd() {
    pwd
}

# Get directory of the calling script file
function get_script_dir() {
    dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
}

# Update the mbf framework installation via git pull
# Usage: mbf_update [branch]
function mbf_update() {
    local branch="${1:-}"
    local target_dir="${MBF_HOME}"
    local dryrun="${MBF_DRYRUN:-${I7R_DRYRUN:-0}}"

    if [ ! -d "${target_dir}/.git" ]; then
        print_with_color "Cannot update mbf: '${target_dir}' is not a git repository." "red" >&2
        return 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        print_with_color "Cannot update mbf: 'git' is not installed." "red" >&2
        return 1
    fi

    local git_cmd="git -C \"$target_dir\" pull --ff-only"
    if [ -n "$branch" ]; then
        git_cmd="git -C \"$target_dir\" pull --ff-only origin \"$branch\""
    fi

    print_with_color "Updating mbf framework in ${target_dir}..." "cyan"
    if [ "$dryrun" == "1" ]; then
        print_with_color "[DRYRUN] Would run: $git_cmd" "yellow"
        return 0
    fi

    if eval "$git_cmd"; then
        chmod +x "${target_dir}/bin/mbf" "${target_dir}/framework.sh" 2>/dev/null || true
        print_with_color "mbf framework updated successfully." "green"
        return 0
    else
        print_with_color "Failed to update mbf framework." "red" >&2
        return 1
    fi
}

##########
# Section 1. Basic functions

# Check if a function exists in current shell
function function_exists() {
    [ "$(type -t "$1")" == "function" ]
}

# Check if needle ($1) is in haystack ($2...)
# Outputs "yes" or "no"
function in_list() {
    local NEEDLE="$1"
    shift
    local line

    for line in "$@"; do
        if [ "$line" == "$NEEDLE" ]; then
            echo "yes"
            return 0
        fi
    done

    echo "no"
    return 0
}

# Check if file ($1) contains string ($2...)
# Outputs "yes" or "no"
function in_file() {
    local FILE="$1"
    shift
    local NEEDLE="$*"

    if [ -f "$FILE" ] && grep -Fq "$NEEDLE" "$FILE"; then
        echo "yes"
    else
        echo "no"
    fi
}

##########
# Section 2. Load core built-in modules (log, exec, check)

mbf_use log exec check

##########
# Section 3. Initialize framework

function init() {
    if [ "${SUDO_REQUIRED:-0}" == "1" ]; then
        initialize_sudo
    fi
}
init
