#!/usr/bin/env bash
# @mbf-module: log
# @mbf-rank: ••••
# ==============================================================================
# mbf core library: log
# Structured terminal logging, extension diagnostics, stack traces & file sink
#
# Environment Variables:
#   MBF_LOG       : Set to "1" to append all logs/errors to MBF_LOG_FILE
#   MBF_LOG_FILE  : Log file path (default: /tmp/mbf.log)
#   MBF_DEBUG     : Set to "1" to enable debug logs, file logging on error, and stack traces
#   MBF_DEBUG_EXT : Set to "1" to trace custom extension & template resolution
#   NO_COLOR      : Set to non-empty to disable ANSI terminal colors
# ==============================================================================

# mbf:state_start
MBF_LOG_FILE="${MBF_LOG_FILE:-/tmp/mbf.log}"
# mbf:state_end

function mbf::log::is_file_enabled() {
    [ "${MBF_LOG:-0}" == "1" ]
}

function mbf::log::is_debug() {
    [ "${MBF_DEBUG:-0}" == "1" ]
}

function mbf::log::is_debug_ext() {
    [ "${MBF_DEBUG_EXT:-0}" == "1" ] || [ "${MBF_DEBUG:-0}" == "1" ]
}

function _mbf_color_code() {
    case "${1:-yellow}" in
        red)    printf '\033[0;31m' ;;
        green)  printf '\033[0;32m' ;;
        yellow) printf '\033[1;33m' ;;
        blue)   printf '\033[0;34m' ;;
        purple) printf '\033[0;35m' ;;
        cyan)   printf '\033[0;36m' ;;
        white)  printf '\033[1;37m' ;;
        *)      printf '\033[1;33m' ;;
    esac
}

# Append a plain-text timestamped entry to MBF_LOG_FILE
function mbf::log::write_file() {
    local level="$1"
    shift
    local target="${MBF_LOG_FILE:-/tmp/mbf.log}"
    local ts
    ts="$(date +'%Y-%m-%d / T%H:%M:%S%z')"
    mkdir -p "$(dirname "$target")" 2>/dev/null || true
    printf '%s [%s] %b\n' "$ts" "$level" "$*" >> "$target"
}

# Single central logging sink
function _mbf_log() {
    local level="$1"
    local color="$2"
    shift 2
    local msg="$*"
    local ts
    ts="$(date +'%Y-%m-%d / T%H:%M:%S%z')"

    if [ -n "${NO_COLOR:-}" ]; then
        printf '%s [%s] %b\n' "$ts" "$level" "$msg"
    else
        local c_code
        c_code="$(_mbf_color_code "$color")"
        printf '\033[0;34m%s %b[%s] %b\033[0m\n' "$ts" "$c_code" "$level" "$msg"
    fi

    if mbf::log::is_file_enabled || { [ "$level" == "ERROR" ] && mbf::log::is_debug; }; then
        mbf::log::write_file "$level" "$msg"
    fi
}

function mbf::log::info() {
    _mbf_log "INFO" "cyan" "$*"
}

function mbf::log::ok() {
    _mbf_log "OK" "green" "$*"
}

function mbf::log::warn() {
    _mbf_log "WARN" "yellow" "$*" >&2
}

function mbf::log::error() {
    _mbf_log "ERROR" "red" "$*" >&2
    if mbf::log::is_debug; then
        mbf::log::stack_trace >&2
    fi
}

function mbf::log::debug() {
    if mbf::log::is_debug; then
        local src="${BASH_SOURCE[1]:-script}"
        local line="${BASH_LINENO[0]:-0}"
        local fn="${FUNCNAME[1]:-main}"
        local loc
        loc="$(basename "$src"):${line}:${fn}"
        _mbf_log "DEBUG" "purple" "(${loc}) $*" >&2
        if ! mbf::log::is_file_enabled; then
            mbf::log::write_file "DEBUG" "(${loc}) $*"
        fi
    fi
}

# Dedicated logger for troubleshooting custom extensions, module loading & template resolution
function mbf::log::debug_ext() {
    if mbf::log::is_debug_ext; then
        local src="${BASH_SOURCE[1]:-framework}"
        local line="${BASH_LINENO[0]:-0}"
        local loc
        loc="$(basename "$src"):${line}"
        _mbf_log "EXT-DEBUG" "purple" "(${loc}) $*" >&2
        if ! mbf::log::is_file_enabled; then
            mbf::log::write_file "EXT-DEBUG" "(${loc}) $*"
        fi
    fi
}

# Print current bash call stack
function mbf::log::stack_trace() {
    local i depth="${#FUNCNAME[@]}"
    printf '  Stack trace:\n'
    for ((i = 1; i < depth; i++)); do
        printf '    at %s (%s:%s)\n' "${FUNCNAME[$i]:-main}" "${BASH_SOURCE[$i]:-unknown}" "${BASH_LINENO[$((i - 1))]:-0}"
    done
}

function mbf::log::xtrace_on() {
    export PS4='+(${BASH_SOURCE##*/}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -x
}

function mbf::log::xtrace_off() {
    set +x
}

# Intentional fatal termination helper
function mbf::die() {
    mbf::log::error "$*"
    exit 1
}
