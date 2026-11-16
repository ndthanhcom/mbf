#!/usr/bin/env bash
# @mbf-module: log
# @mbf-rank: ••••
# ==============================================================================
# mbf core library: log
# Structured terminal logging, extension diagnostics, stack traces & file sink
#
# Output contract (which stream each level writes to):
#   info, ok          -> stdout (default, backward compatible) or stderr when MBF_LOG_STDERR=1
#   debug, debug_ext  -> stderr
#   warn, error       -> stderr
# Tip: set MBF_LOG_STDERR=1 so `out="$(some_mbf_function)"` captures only real data,
# never log lines. Scripts created with `mbf new` enable it by default.
#
# Environment Variables:
#   MBF_LOG        : Set to "1" to append all logs/errors to MBF_LOG_FILE
#   MBF_LOG_FILE   : Log file path (default: /tmp/mbf.log)
#   MBF_LOG_STDERR : Set to "1" to send info/ok messages to stderr as well
#   MBF_DEBUG      : Set to "1" to enable debug logs, file logging on error, and stack traces
#   MBF_DEBUG_EXT  : Set to "1" to trace custom extension & template resolution
#   NO_COLOR       : Set to non-empty to disable ANSI terminal colors
#
# Messages are printed literally (`%s`): backslashes such as `C:\new` are never
# interpreted as escape sequences.
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

# ISO-8601 local timestamp, e.g. 2026-11-16T01:30:00+0700
function _mbf_log_ts() {
    date +'%Y-%m-%dT%H:%M:%S%z'
}

# Append a plain-text timestamped entry to MBF_LOG_FILE
function mbf::log::write_file() {
    local level="$1"
    shift
    local target="${MBF_LOG_FILE:-/tmp/mbf.log}"
    mkdir -p "$(dirname "$target")" 2>/dev/null || true
    printf '%s [%s] %s\n' "$(_mbf_log_ts)" "$level" "$*" >> "$target"
}

# Single central logging sink: prints one formatted line to the *current* stdout.
# Callers decide the stream by redirecting (`>&2`).
function _mbf_log() {
    local level="$1"
    local color="$2"
    shift 2
    local msg="$*"
    local ts
    ts="$(_mbf_log_ts)"

    if [ -n "${NO_COLOR:-}" ]; then
        printf '%s [%s] %s\n' "$ts" "$level" "$msg"
    else
        printf '\033[0;34m%s %s[%s] %s\033[0m\n' "$ts" "$(_mbf_color_code "$color")" "$level" "$msg"
    fi

    if mbf::log::is_file_enabled || { [ "$level" == "ERROR" ] && mbf::log::is_debug; }; then
        mbf::log::write_file "$level" "$msg"
    fi
}

# Print an info/ok line to stdout, or to stderr when MBF_LOG_STDERR=1
function _mbf_log_out() {
    if [ "${MBF_LOG_STDERR:-0}" == "1" ]; then
        _mbf_log "$@" >&2
    else
        _mbf_log "$@"
    fi
}

function mbf::log::info() {
    _mbf_log_out "INFO" "cyan" "$*"
}

function mbf::log::ok() {
    _mbf_log_out "OK" "green" "$*"
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

# Debug line with caller location `(file:line:function)`; also written to MBF_LOG_FILE
function mbf::log::debug() {
    if mbf::log::is_debug; then
        local loc
        loc="$(basename "${BASH_SOURCE[1]:-script}"):${BASH_LINENO[0]:-0}:${FUNCNAME[1]:-main}"
        _mbf_log "DEBUG" "purple" "(${loc}) $*" >&2
        if ! mbf::log::is_file_enabled; then
            mbf::log::write_file "DEBUG" "(${loc}) $*"
        fi
    fi
    return 0
}

# Dedicated logger for troubleshooting custom extensions, module loading & template resolution
function mbf::log::debug_ext() {
    if mbf::log::is_debug_ext; then
        local loc
        loc="$(basename "${BASH_SOURCE[1]:-framework}"):${BASH_LINENO[0]:-0}"
        _mbf_log "EXT-DEBUG" "purple" "(${loc}) $*" >&2
        if ! mbf::log::is_file_enabled; then
            mbf::log::write_file "EXT-DEBUG" "(${loc}) $*"
        fi
    fi
    return 0
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

# Intentional fatal termination helper (one of the two terminal actions in mbf,
# together with `-h/--help` in `mbf::args::parse`)
function mbf::die() {
    mbf::log::error "$*"
    exit 1
}
