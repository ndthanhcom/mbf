#!/usr/bin/env bash
# ==============================================================================
# mbf — Micro Bash Framework
# Core loader, dependency & custom extension resolver, and base predicates
#
# Conventions used across every mbf module:
#   - `# mbf:requires a b`  : modules loaded (in order) before this file is sourced.
#   - `# mbf:state_start` / `# mbf:state_end` : module-level variables. `mbf export`
#     copies only these lines (plus reachable functions) into standalone scripts.
#   - Public functions are `mbf::<module>::<fn>`; private helpers are `_mbf_<module>_<fn>`.
#   - Library functions never `exit`; they return 0 (success) or non-zero (failure).
#   - Every function is safe under `mbf::strict` (`set -Eeuo pipefail`).
# ==============================================================================

if [ -n "${MBF_CORE_LOADED:-}" ]; then
    return 0 2>/dev/null || true
fi

# mbf relies on Bash 4+ features (`${var,,}`, `declare -A`, `printf -v`).
# macOS ships Bash 3.2 by default: install a modern Bash with `brew install bash`.
if [ "${MBF_BASH_MAJOR_OVERRIDE:-${BASH_VERSINFO[0]:-0}}" -lt 4 ]; then
    printf 'mbf: Bash >= 4.0 is required (current: %s). On macOS run: brew install bash\n' "${BASH_VERSION:-unknown}" >&2
    return 1 2>/dev/null || exit 1
fi
MBF_CORE_LOADED=1
MBF_VERSION="1.0.0"

# mbf:state_start
MBF_HOME="${MBF_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
MBF_SCRIPT_DIR="${MBF_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)}"
MBF_EXT_PATH="${MBF_EXT_PATH:-}"
MBF_LOADED_MODULES="${MBF_LOADED_MODULES:- }"
# mbf:state_end

# Monthly (30-day) periodic version check settings (not included in exported scripts)
MBF_UPDATE_CHECK_INTERVAL="${MBF_UPDATE_CHECK_INTERVAL:-2592000}"
MBF_UPDATE_CHECK_FILE="${MBF_UPDATE_CHECK_FILE:-${MBF_HOME}/.version_check}"
MBF_UPDATE_URL="${MBF_UPDATE_URL:-https://raw.githubusercontent.com/ndthanhcom/mbf/master/framework.sh}"

# Print current mbf framework version
function mbf::version() {
    printf '%s\n' "${MBF_VERSION}"
}

# Return 0 if semantic version $1 is strictly greater than $2 (e.g. `1.1.0` > `1.0.0`)
function _mbf_version_gt() {
    local v1="${1#v}" v2="${2#v}"
    [ "$v1" == "$v2" ] && return 1
    local IFS='.'
    local -a a1=() a2=()
    read -r -a a1 <<< "$v1"
    read -r -a a2 <<< "$v2"
    local i n1 n2
    for i in 0 1 2; do
        n1="${a1[$i]:-0}"
        n2="${a2[$i]:-0}"
        n1="${n1%%[^0-9]*}"
        n2="${n2%%[^0-9]*}"
        if [ "${n1:-0}" -gt "${n2:-0}" ]; then
            return 0
        elif [ "${n1:-0}" -lt "${n2:-0}" ]; then
            return 1
        fi
    done
    return 1
}

# Periodically check (once every 30 days) whether a newer version of mbf is available.
# Caches `<epoch_timestamp> <remote_version>` in `$MBF_HOME/.version_check`.
# Skipped automatically in non-interactive shells, dry-run mode, CI, or when
# `MBF_NO_UPDATE_CHECK=1`, unless `--force` is passed.
# Usage: mbf::check_update [--force]
function mbf::check_update() {
    local force=0
    [ "${1:-}" == "--force" ] && force=1

    if [ "$force" -eq 0 ]; then
        if [ "${MBF_NO_UPDATE_CHECK:-0}" == "1" ] || [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
            return 0
        fi
        if mbf::is_dryrun || [ ! -t 2 ]; then
            return 0
        fi
    fi

    local now last_ts=0 cached_ver="" remote_ver=""
    now="$(date +%s)"
    local cache_file="${MBF_UPDATE_CHECK_FILE:-${MBF_HOME}/.version_check}"

    if [ -r "$cache_file" ]; then
        read -r last_ts cached_ver < "$cache_file" 2>/dev/null || true
    fi

    if [ "$force" -eq 1 ] || [ -z "$cached_ver" ] || [ $((now - ${last_ts:-0})) -ge "${MBF_UPDATE_CHECK_INTERVAL:-2592000}" ]; then
        if command -v curl >/dev/null 2>&1; then
            remote_ver="$(curl -fsSL --connect-timeout 2 --max-time 3 "$MBF_UPDATE_URL" 2>/dev/null | grep -m1 '^MBF_VERSION=' | sed -E 's/^MBF_VERSION="([^"]+)".*/\1/' | tr -d '\r' || true)"
        fi
        if [ -n "$remote_ver" ]; then
            cached_ver="$remote_ver"
        else
            cached_ver="${cached_ver:-$MBF_VERSION}"
        fi
        mkdir -p "$(dirname "$cache_file")" 2>/dev/null || true
        printf '%s %s\n' "$now" "$cached_ver" > "$cache_file" 2>/dev/null || true
    fi

    if [ -n "$cached_ver" ] && _mbf_version_gt "$cached_ver" "$MBF_VERSION"; then
        mbf::log::warn "A new version of mbf is available: v${cached_ver} (current: v${MBF_VERSION}). Run 'mbf update' to upgrade."
    fi
    return 0
}

# Check if a module or plugin is already loaded
function mbf::is_loaded() {
    [[ "${MBF_LOADED_MODULES:- }" == *" $1 "* ]]
}

# Resolve module or plugin name to its file path:
# 1. Explicit relative/absolute path
# 2. Directories in MBF_EXT_PATH and caller script's lib/ or plugins/
# 3. Built-in MBF_HOME/lib/ and MBF_HOME/plugins/
# Usage: _mbf_resolve_path <name_or_path> [caller_dir]
function _mbf_resolve_path() {
    local raw="$1"
    local caller_dir="${2:-${MBF_SCRIPT_DIR:-.}}"
    local name="${raw%.sh}"

    # 1. Direct file path
    if [[ "$raw" == */* ]] || [[ "$raw" == *.sh ]]; then
        if [ -f "$raw" ]; then
            printf '%s\n' "$raw"
            return 0
        elif [ -f "${caller_dir}/${raw}" ]; then
            printf '%s\n' "${caller_dir}/${raw}"
            return 0
        fi
    fi

    # 2. Custom extension directories (MBF_EXT_PATH + caller script's lib/ and plugins/)
    local search_dirs="${MBF_EXT_PATH:+${MBF_EXT_PATH}:}${caller_dir}/lib:${caller_dir}/plugins"
    local IFS=':' ext_dir sub
    for ext_dir in $search_dirs; do
        [ -n "$ext_dir" ] || continue
        for sub in "" "/lib" "/plugins"; do
            if [ -f "${ext_dir}${sub}/${name}.sh" ]; then
                printf '%s\n' "${ext_dir}${sub}/${name}.sh"
                return 0
            fi
        done
    done

    # 3. Built-in MBF core libraries and plugins
    for sub in lib plugins; do
        if [ -f "${MBF_HOME}/${sub}/${name}.sh" ]; then
            printf '%s\n' "${MBF_HOME}/${sub}/${name}.sh"
            return 0
        fi
    done
    return 1
}

# Print the space-separated module list declared in a file's `# mbf:requires` header
# (prints nothing when the header is absent; never fails under `pipefail`)
function _mbf_read_requires() {
    local line
    line="$(grep -m1 '^# mbf:requires ' "$1" 2>/dev/null || true)"
    line="${line#\# mbf:requires }"
    printf '%s\n' "${line//$'\r'/}"
}

# Load one or more mbf libraries, plugins, or custom extensions, resolving `# mbf:requires`
# Usage: mbf::use log config monitor
function mbf::use() {
    local mod mod_key mod_file reqs req
    for mod in "$@"; do
        mod_key="$(basename "${mod%.sh}")"
        if mbf::is_loaded "$mod_key"; then
            continue
        fi

        if ! mod_file="$(_mbf_resolve_path "$mod")"; then
            if declare -F mbf::log::debug_ext >/dev/null 2>&1; then
                mbf::log::debug_ext "Failed to resolve module '$mod' (MBF_EXT_PATH='${MBF_EXT_PATH:-}', MBF_SCRIPT_DIR='${MBF_SCRIPT_DIR:-}', MBF_HOME='${MBF_HOME}')"
            fi
            printf 'mbf::use: module or extension "%s" not found (searched MBF_EXT_PATH, %s/{lib,plugins}, %s/{lib,plugins})\n' "$mod" "${MBF_SCRIPT_DIR:-.}" "$MBF_HOME" >&2
            return 1
        fi

        # Mark as loaded *before* resolving requirements to break circular dependencies
        MBF_LOADED_MODULES="${MBF_LOADED_MODULES}${mod_key} "

        reqs="$(_mbf_read_requires "$mod_file")"
        if declare -F mbf::log::debug_ext >/dev/null 2>&1; then
            mbf::log::debug_ext "Loading module '$mod_key' from '$mod_file'${reqs:+ (requires: $reqs)}"
        fi

        for req in $reqs; do
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

# Enable strict execution mode (`set -Eeuo pipefail`) with an ERR trap that logs
# the failing file, line, command and exit status before the script stops.
function mbf::strict() {
    mbf::use log
    set -Eeuo pipefail
    trap '_mbf_on_err "${BASH_SOURCE[0]:-$0}" "${LINENO}" "${BASH_COMMAND}" "$?"' ERR
}

function _mbf_on_err() {
    mbf::log::error "Error in $1:$2 — '$3' exited with status $4"
}

# Return 0 if dry-run mode (`MBF_DRYRUN=1`) is active
function mbf::is_dryrun() {
    [ "${MBF_DRYRUN:-0}" == "1" ]
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

# Replace the content of <file> with stdin while preserving its mode, owner and
# symlink target. Writes atomically (sibling temp + mv) whenever possible.
# Usage: printf 'new content\n' | _mbf_replace_file /etc/app.conf
function _mbf_replace_file() {
    local file="$1"
    local stage="${file}.mbf.tmp.$$"

    # Regular existing file: copy it first (cp -p keeps mode/owner), then overwrite + rename
    if [ -f "$file" ] && [ ! -L "$file" ] && cp -p "$file" "$stage" 2>/dev/null; then
        if cat > "$stage" && mv -f "$stage" "$file"; then
            return 0
        fi
        rm -f "$stage"
        return 1
    fi

    # New file or symlink: buffer stdin first (the reader may be reading <file>), then write through
    local content
    content="$(cat; printf 'x')"
    content="${content%x}"
    mkdir -p "$(dirname "$file")" 2>/dev/null || true
    printf '%s' "$content" > "$file"
}

# Portable sorted `find` emitting NUL-delimited paths (`-print0` + `LC_ALL=C sort -z`
# on GNU/Git Bash, falling back to `LC_ALL=C sort | tr '\n' '\0'` on macOS BSD / BusyBox).
# Usage: while IFS= read -r -d '' f; do ...; done < <(_mbf_find_sorted <find_args...>)
function _mbf_find_sorted() {
    if printf 'a\0b\0' | sort -z >/dev/null 2>&1; then
        find "$@" -print0 2>/dev/null | LC_ALL=C sort -z
    else
        find "$@" 2>/dev/null | LC_ALL=C sort | tr '\n' '\0'
    fi
}

# Update the mbf framework installation via git pull
# Usage: mbf::update [branch]
function mbf::update() {
    mbf::use log
    local branch="${1:-}"
    if [ ! -e "${MBF_HOME}/.git" ]; then
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

# Load core logging by default and run non-blocking monthly version check
mbf::use log
mbf::check_update
