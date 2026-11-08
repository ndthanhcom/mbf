#!/usr/bin/env bash
# mbf:requires log
# ==============================================================================
# mbf core library: check
# Command, version, environment variable, and OS validation helpers
# Returns 0/1 status codes (never calls exit).
# ==============================================================================

# Check if a command exists in PATH (and optionally matches expected version)
# Usage: mbf::check::cmd <cmd_name> [expected_version]
function mbf::check::cmd() {
    local cmd_name="$1"
    local expected_ver="${2:-}"

    if ! command -v "$cmd_name" >/dev/null 2>&1; then
        mbf::log::warn "Required program '$cmd_name' is not installed."
        return 1
    fi

    if [ -n "$expected_ver" ]; then
        local actual_ver
        actual_ver="$("$cmd_name" --version 2>/dev/null | head -n 1 | awk '{print $NF}')"
        if [ "$actual_ver" != "$expected_ver" ]; then
            mbf::log::error "Program '$cmd_name' version '$expected_ver' required (found: '$actual_ver')."
            return 1
        fi
    fi
    return 0
}

# Verify multiple commands are installed (or check $MBF_REQUIREMENTS if no args given)
# Usage: mbf::check::cmds git curl jq
function mbf::check::cmds() {
    local -a list=("$@")
    if [ "${#list[@]}" -eq 0 ] && [ -n "${MBF_REQUIREMENTS:-}" ]; then
        read -r -a list <<< "$MBF_REQUIREMENTS"
    fi

    local cmd
    for cmd in "${list[@]}"; do
        mbf::check::cmd "$cmd" || return 1
    done
    return 0
}

# Verify one or more environment variables are set and non-empty
# Usage: mbf::check::env DB_HOST DB_USER
function mbf::check::env() {
    local var_name
    for var_name in "$@"; do
        if [ -z "${!var_name:-}" ]; then
            mbf::log::error "Required environment variable '$var_name' is not set."
            return 1
        fi
    done
    return 0
}

# Verify script is running as root (UID 0)
function mbf::check::root() {
    if [ "$(id -u)" != "0" ]; then
        mbf::log::error "This operation requires root privileges."
        return 1
    fi
    return 0
}

function mbf::check::is_linux() {
    [[ "$(uname -s)" == "Linux" ]]
}

function mbf::check::is_macos() {
    [[ "$(uname -s)" == "Darwin" ]]
}
