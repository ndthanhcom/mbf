#!/usr/bin/env bash
# ==============================================================================
# mbf — Micro Bash Framework
# Core loader, dependency resolver, and base predicates
# ==============================================================================

if [ -n "${MBF_CORE_LOADED:-}" ]; then
    return 0 2>/dev/null || true
fi
MBF_CORE_LOADED=1

# mbf:state_start
MBF_HOME="${MBF_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
MBF_LOADED_MODULES="${MBF_LOADED_MODULES:- }"
# mbf:state_end

# Check if a module or plugin is already loaded
function mbf::is_loaded() {
    [[ "${MBF_LOADED_MODULES:- }" == *" $1 "* ]]
}

# Resolve module or plugin name to its file path in lib/ or plugins/
function _mbf_resolve_path() {
    local name="${1%.sh}"
    if [ -f "${MBF_HOME}/lib/${name}.sh" ]; then
        printf '%s\n' "${MBF_HOME}/lib/${name}.sh"
        return 0
    elif [ -f "${MBF_HOME}/plugins/${name}.sh" ]; then
        printf '%s\n' "${MBF_HOME}/plugins/${name}.sh"
        return 0
    fi
    return 1
}

# Load one or more mbf libraries or plugins, automatically resolving `# mbf:requires` headers
# Usage: mbf::use log config monitor
function mbf::use() {
    local mod mod_file reqs req
    for mod in "$@"; do
        mod="${mod%.sh}"
        if mbf::is_loaded "$mod"; then
            continue
        fi

        if ! mod_file="$(_mbf_resolve_path "$mod")"; then
            printf 'mbf::use: module or plugin "%s" not found in %s/{lib,plugins}\n' "$mod" "$MBF_HOME" >&2
            return 1
        fi

        MBF_LOADED_MODULES="${MBF_LOADED_MODULES}${mod} "

        # Resolve `# mbf:requires mod1 mod2` header before sourcing
        reqs="$(grep -m1 '^# mbf:requires ' "$mod_file" 2>/dev/null | sed 's/^# mbf:requires //')"
        for req in $reqs; do
            req="${req%$'\r'}"
            mbf::use "$req" || return 1
        done

        # shellcheck disable=SC1090
        source "$mod_file"
    done
}

# Explicit framework initialization (optional sudo pre-authentication)
function mbf::init() {
    if [ "${MBF_SUDO:-0}" == "1" ]; then
        mbf::use exec
        mbf::exec::init_sudo
    fi
}

# Enable strict execution mode (`set -Eeuo pipefail`) with error trap
function mbf::strict() {
    mbf::use log
    set -Eeuo pipefail
    trap '_mbf_on_err "${BASH_SOURCE[0]}" "${LINENO}" "${BASH_COMMAND}" "$?"' ERR
}

function _mbf_on_err() {
    mbf::log::error "Error in $1:$2 — '$3' exited with status $4"
}

# Return 0 if dry-run mode (`MBF_DRYRUN=1`) is active
function mbf::is_dryrun() {
    [ "${MBF_DRYRUN:-0}" == "1" ]
}

# Return 0 if a bash function is defined
function mbf::function_exists() {
    declare -F "$1" >/dev/null 2>&1
}

# Return 0 if needle ($1) is present in remaining arguments ($2...)
function mbf::in_list() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [ "$item" == "$needle" ] && return 0
    done
    return 1
}

# Return 0 if file ($1) contains fixed string ($2...)
function mbf::in_file() {
    local file="$1"
    shift
    [ -f "$file" ] && grep -Fq "$*" "$file"
}

# Print directory of the calling script
function mbf::script_dir() {
    cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd
}

# Update the mbf framework installation via git pull
# Usage: mbf::update [branch]
function mbf::update() {
    mbf::use log
    local branch="${1:-}"
    if [ ! -d "${MBF_HOME}/.git" ]; then
        mbf::log::error "Cannot update mbf: '${MBF_HOME}' is not a git repository."
        return 1
    fi
    if ! command -v git >/dev/null 2>&1; then
        mbf::log::error "Cannot update mbf: 'git' is not installed."
        return 1
    fi

    local -a cmd=(git -C "$MBF_HOME" pull --ff-only)
    [ -n "$branch" ] && cmd+=(origin "$branch")

    mbf::log::info "Updating mbf in ${MBF_HOME}..."
    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would run: ${cmd[*]}"
        return 0
    fi

    if "${cmd[@]}"; then
        chmod +x "${MBF_HOME}/bin/mbf" "${MBF_HOME}/framework.sh" 2>/dev/null || true
        mbf::log::ok "mbf updated successfully."
        return 0
    fi
    mbf::log::error "Failed to update mbf."
    return 1
}

# Load core logging by default
mbf::use log
