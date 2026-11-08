#!/usr/bin/env bash
# mbf module: check
# Environment, OS, and program validation utilities

# If $I7R_REQUIREMENTS or $MBF_REQUIREMENTS is set, check if all requirements are met
function check_requirements() {
    local reqs="${MBF_REQUIREMENTS:-${I7R_REQUIREMENTS:-}}"
    local req
    for req in $reqs; do
        if ! command -v "$req" >/dev/null 2>&1; then
            echo "required program \"$req\" could not be found"
            exit 1
        fi
    done
}

# Check if a program is installed (and optionally matches version) before running
# param $1: program name
# param $2: trigger ("exit" or "warning", default: "warning")
# param $3: required version (optional)
function validate_program() {
    local req_name="$1"
    local trigger="${2:-warning}"
    local version="${3:-}"

    if ! command -v "$req_name" >/dev/null 2>&1; then
        if [ "$trigger" == "exit" ]; then
            print_with_color "required program \"$req_name\" could not be found" red
            exit 1
        else
            print_with_color "required program \"$req_name\" could not be found" yellow
        fi
        return 1
    fi

    local program
    program="$(command -v "$req_name")"

    if [ -n "$version" ]; then
        local program_version
        program_version="$("$program" --version 2>/dev/null | head -n 1 | awk '{print $NF}')"
        if [ "$program_version" != "$version" ]; then
            print_with_color "required program \"$req_name\" version $version is required (found: $program_version)" red
            if [ "$trigger" == "exit" ]; then
                exit 1
            fi
            return 1
        fi
    fi

    return 0
}

# Ensure required environment variables are set and non-empty
# Usage: require_env DB_HOST DB_USER
function require_env() {
    local var_name
    for var_name in "$@"; do
        if [ -z "${!var_name:-}" ]; then
            print_with_color "Required environment variable \"$var_name\" is not set" red
            return 1
        fi
    done
    return 0
}

# Ensure script is running as root
function require_root() {
    if [ "$(id -u)" != "0" ]; then
        print_with_color "This script must be run as root" red
        return 1
    fi
    return 0
}

function is_linux() {
    [[ "$(uname -s)" == "Linux" ]]
}

function is_macos() {
    [[ "$(uname -s)" == "Darwin" ]]
}
