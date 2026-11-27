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

# mbf relies on Bash 4.3+ features (`local -n` namerefs, `${var,,}`, `declare -A`, `printf -v`).
# macOS ships Bash 3.2 by default: install a modern Bash with `brew install bash`.
_mbf_bash_major="${MBF_BASH_MAJOR_OVERRIDE:-${BASH_VERSINFO[0]:-0}}"
_mbf_bash_minor="${MBF_BASH_MINOR_OVERRIDE:-${BASH_VERSINFO[1]:-0}}"
if [ "$_mbf_bash_major" -lt 4 ] || { [ "$_mbf_bash_major" -eq 4 ] && [ "$_mbf_bash_minor" -lt 3 ]; }; then
    printf 'mbf: Bash >= 4.3 is required (current: %s). On macOS run: brew install bash\n' "${BASH_VERSION:-unknown}" >&2
    return 1 2>/dev/null || exit 1
fi
unset _mbf_bash_major _mbf_bash_minor
MBF_CORE_LOADED=1

# mbf:state_start
MBF_VERSION="1.0.0"
export MBF_API_VERSION="1"
MBF_HOME="${MBF_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
MBF_SCRIPT_DIR="${MBF_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)}"
MBF_EXT_PATH="${MBF_EXT_PATH:-}"
MBF_USER_DATA_DIR="${MBF_USER_DATA_DIR:-${XDG_DATA_HOME:-${HOME:-/tmp}/.local/share}/mbf}"
MBF_USER_PLUGINS_DIR="${MBF_USER_PLUGINS_DIR:-${MBF_USER_DATA_DIR}/plugins}"
MBF_RUNTIME_DIR="${MBF_RUNTIME_DIR:-${XDG_RUNTIME_DIR:+${XDG_RUNTIME_DIR}/mbf}}"
MBF_RUNTIME_DIR="${MBF_RUNTIME_DIR:-${TMPDIR:-/tmp}/mbf-${UID:-$(id -u 2>/dev/null || echo 0)}}"
MBF_LOADED_MODULES="${MBF_LOADED_MODULES:- }"
# mbf:state_end

# Monthly (30-day) periodic version check settings (not included in exported scripts)
MBF_UPDATE_CHECK_INTERVAL="${MBF_UPDATE_CHECK_INTERVAL:-2592000}"
MBF_UPDATE_CHECK_FILE="${MBF_UPDATE_CHECK_FILE:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/mbf/version_check}"
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
# Caches `<epoch_timestamp> <remote_version>` in `${XDG_CACHE_HOME:-~/.cache}/mbf/version_check`.
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
    local cache_file="${MBF_UPDATE_CHECK_FILE:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/mbf/version_check}"

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
        mbf::log::warn "A new version of mbf is available: v${cached_ver} (current: v${MBF_VERSION}). Run 'mbf version update' to upgrade."
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

    # 2. Custom extension directories (MBF_EXT_PATH + caller script's lib/ and plugins/ + user plugins dir)
    local user_plugins="${MBF_USER_PLUGINS_DIR:-${XDG_DATA_HOME:-${HOME:-/tmp}/.local/share}/mbf/plugins}"
    local search_dirs="${MBF_EXT_PATH:+${MBF_EXT_PATH}:}${caller_dir}/lib:${caller_dir}/plugins:${user_plugins}"
    local -a _ext_dirs=()
    local ext_dir sub
    IFS=':' read -r -a _ext_dirs <<< "$search_dirs"
    for ext_dir in "${_ext_dirs[@]}"; do
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

# Load one or more mbf libraries or plugins, resolving `# mbf:requires`
# Usage: mbf::use log config notify
function mbf::use() {
    local mod mod_key mod_file reqs req
    for mod in "$@"; do
        mod_key="$(basename "${mod%.sh}")"
        if mbf::is_loaded "$mod_key"; then
            continue
        fi

        if ! mod_file="$(_mbf_resolve_path "$mod")"; then
            if declare -F mbf::log::debug_ext >/dev/null 2>&1; then
                mbf::log::debug_ext "Failed to resolve library or plugin '$mod' (MBF_EXT_PATH='${MBF_EXT_PATH:-}', MBF_SCRIPT_DIR='${MBF_SCRIPT_DIR:-}', MBF_HOME='${MBF_HOME}')"
            fi
            printf 'mbf::use: library or plugin "%s" not found (searched MBF_EXT_PATH, %s/{lib,plugins}, %s/{lib,plugins})\n' "$mod" "${MBF_SCRIPT_DIR:-.}" "$MBF_HOME" >&2
            return 1
        fi

        # Mark as loaded *before* resolving requirements to break circular dependencies
        MBF_LOADED_MODULES="${MBF_LOADED_MODULES}${mod_key} "

        reqs="$(_mbf_read_requires "$mod_file")"
        if declare -F mbf::log::debug_ext >/dev/null 2>&1; then
            mbf::log::debug_ext "Loading library/plugin '$mod_key' from '$mod_file'${reqs:+ (requires: $reqs)}"
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
        declare -F mbf::use >/dev/null 2>&1 && mbf::use exec
        mbf::exec::init_sudo
    fi
}

# Enable strict execution mode (`set -Eeuo pipefail`) with an ERR trap that logs
# the failing file, line, command and exit status before the script stops.
function mbf::strict() {
    declare -F mbf::use >/dev/null 2>&1 && mbf::use log
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

# List available Git version tags in `$MBF_HOME` (marks current version)
# Usage: mbf::list_versions
function mbf::list_versions() {
    mbf::use log
    if [ ! -e "${MBF_HOME}/.git" ] || ! command -v git >/dev/null 2>&1; then
        mbf::log::error "Cannot list versions: '${MBF_HOME}' is not a git repository or git is missing."
        return 1
    fi

    local current_ref tags tag
    current_ref="$(git -C "$MBF_HOME" describe --tags --exact-match 2>/dev/null || git -C "$MBF_HOME" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "v${MBF_VERSION}")"
    printf 'Current: v%s (%s)\n' "${MBF_VERSION}" "$current_ref"
    tags="$(git -C "$MBF_HOME" tag -l --sort=-v:refname 2>/dev/null || git -C "$MBF_HOME" tag -l 2>/dev/null || true)"
    if [ -z "$tags" ]; then
        printf 'No local git tags found. Run `mbf version change <tag>` to fetch from origin.\n'
        return 0
    fi
    while IFS= read -r tag; do
        [ -n "$tag" ] || continue
        if [ "$tag" == "$current_ref" ] || [ "$tag" == "v${MBF_VERSION}" ]; then
            printf '  * %s\n' "$tag"
        else
            printf '    %s\n' "$tag"
        fi
    done <<< "$tags"
}

# Switch the local `$MBF_HOME` installation to a specific Git tag or branch
# (e.g. to match a plugin's `mbf-compat` range before running `mbf export`).
# Usage: mbf::switch_version <tag_or_branch> [--force]
function mbf::switch_version() {
    mbf::use log
    local target="${1:-}"
    local force=0
    [ "${2:-}" == "--force" ] && force=1

    if [ -z "$target" ]; then
        mbf::log::error "mbf::switch_version: <tag_or_branch> is required (e.g. v1.0.0)"
        return 1
    fi
    if [ ! -e "${MBF_HOME}/.git" ] || ! command -v git >/dev/null 2>&1; then
        mbf::log::error "Cannot switch version: '${MBF_HOME}' is not a git repository or git is missing."
        return 1
    fi

    if [ "$force" -eq 0 ] && ! mbf::is_dryrun; then
        if [ -n "$(git -C "$MBF_HOME" status --porcelain 2>/dev/null || true)" ]; then
            mbf::log::error "Cannot switch version: '${MBF_HOME}' has uncommitted changes (commit/stash or pass --force)."
            return 1
        fi
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would fetch tags and checkout '${target}' in ${MBF_HOME}"
        return 0
    fi

    mbf::log::info "Switching mbf in ${MBF_HOME} to '${target}'..."
    git -C "$MBF_HOME" fetch --tags origin >/dev/null 2>&1 || true
    if git -C "$MBF_HOME" checkout "$target"; then
        chmod +x "${MBF_HOME}/bin/mbf" "${MBF_HOME}/framework.sh" 2>/dev/null || true
        local new_ver
        new_ver="$(grep -m1 '^MBF_VERSION=' "${MBF_HOME}/framework.sh" 2>/dev/null | sed -E 's/^MBF_VERSION="([^"]+)".*/\1/' || true)"
        mbf::log::ok "Switched mbf to '${target}' (v${new_ver:-unknown})."
        return 0
    fi
    mbf::log::error "Failed to switch mbf to '${target}'."
    return 1
}

# Load core logging by default (update checks run via interactive `mbf` CLI, never on `source`)
mbf::use log
