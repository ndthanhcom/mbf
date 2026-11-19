#!/usr/bin/env bash
# @mbf-module: log
# ==============================================================================
# mbf core library: log
# Structured terminal logging, extension diagnostics, stack traces & file sink
#
# Output contract (which stream each level writes to):
#   info, ok          -> stderr by default (`MBF_LOG_STDERR=1`), or stdout when `MBF_LOG_STDERR=0`
#   debug, debug_ext  -> stderr
#   warn, error       -> stderr
# Because all logs go to stderr by default, `out="$(some_mbf_function)"` captures
# only real data, never log lines.
#
# Environment Variables:
#   MBF_LOG        : Set to "1" to append all logs/errors to MBF_LOG_FILE
#   MBF_LOG_FILE   : Log file path (default: /tmp/mbf.log)
#   MBF_LOG_STDERR : Set to "1" (default) to write info/ok to stderr; "0" for stdout
#   MBF_DEBUG      : Set to "1" to enable debug logs, file logging on error, and stack traces
#   MBF_DEBUG_EXT  : Set to "1" to trace custom extension & template resolution
#   MBF_LOG_FORMAT : Output format: `text` (default) or `json` (single-line JSON object)
#   MBF_LOG_CI     : Set to "1" to emit GitHub Actions `::warning::`/`::error::` annotations
#   NO_COLOR       : Set to non-empty to disable ANSI terminal colors (also auto-disabled off-TTY)
#   FORCE_COLOR    : Set to "1" to force ANSI colors even when stdout/stderr is not a TTY
#
# Messages are printed literally (`%s`): backslashes such as `C:\new` are never
# interpreted as escape sequences.
# ==============================================================================

# mbf:state_start
MBF_LOG_FILE="${MBF_LOG_FILE:-/tmp/mbf.log}"
MBF_LOG_FORMAT="${MBF_LOG_FORMAT:-text}"
MBF_LOG_REDACT=()
# mbf:state_end

# Register one or more secret strings to be masked as `***` in all log output
# Usage: mbf::log::redact "$API_TOKEN" "$DB_PASS"
function mbf::log::redact() {
    local secret
    for secret in "$@"; do
        [ -n "$secret" ] || continue
        MBF_LOG_REDACT+=("$secret")
    done
}

# Internal helper: replace all registered secrets with `***` (literal, Bash 5.2 safe)
function _mbf_log_mask() {
    local text="$1"
    [ "${#MBF_LOG_REDACT[@]}" -eq 0 ] && { printf '%s' "$text"; return 0; }

    local secret out prefix
    for secret in "${MBF_LOG_REDACT[@]}"; do
        [ -n "$secret" ] || continue
        out=""
        while [[ "$text" == *"$secret"* ]]; do
            prefix="${text%%"$secret"*}"
            out="${out}${prefix}***"
            text="${text#*"$secret"}"
        done
        text="${out}${text}"
    done
    printf '%s' "$text"
}

# Internal helper: minimal JSON string escaper so `log` stays zero-dependency
function _mbf_log_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Internal helper: return 0 if ANSI color should be emitted on current stdout
function _mbf_log_use_color() {
    [ -n "${NO_COLOR:-}" ] && return 1
    [ "${FORCE_COLOR:-0}" == "1" ] && return 0
    [ -t 1 ]
}

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
    local msg
    msg="$(_mbf_log_mask "$*")"
    mkdir -p "$(dirname "$target")" 2>/dev/null || true
    printf '%s [%s] %s\n' "$(_mbf_log_ts)" "$level" "$msg" >> "$target"
}

# Single central logging sink: prints one formatted line to the *current* stdout.
# Callers decide the stream by redirecting (`>&2`).
function _mbf_log() {
    local level="$1"
    local color="$2"
    shift 2
    local msg ts
    msg="$(_mbf_log_mask "$*")"
    ts="$(_mbf_log_ts)"

    if [ "${MBF_LOG_FORMAT:-text}" == "json" ]; then
        printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
            "$(_mbf_log_json_escape "$ts")" \
            "$(_mbf_log_json_escape "$level")" \
            "$(_mbf_log_json_escape "$msg")"
    elif [ "${MBF_LOG_CI:-0}" == "1" ] && [ "$level" == "WARN" ]; then
        printf '::warning::%s\n' "$msg"
    elif [ "${MBF_LOG_CI:-0}" == "1" ] && [ "$level" == "ERROR" ]; then
        printf '::error::%s\n' "$msg"
    elif ! _mbf_log_use_color; then
        printf '%s [%s] %s\n' "$ts" "$level" "$msg"
    else
        printf '\033[0;34m%s %s[%s] %s\033[0m\n' "$ts" "$(_mbf_color_code "$color")" "$level" "$msg"
    fi

    if mbf::log::is_file_enabled || { [ "$level" == "ERROR" ] && mbf::log::is_debug; }; then
        mbf::log::write_file "$level" "$msg"
    fi
}

# Print an info/ok line to stderr by default, or to stdout when MBF_LOG_STDERR=0
function _mbf_log_out() {
    if [ "${MBF_LOG_STDERR:-1}" == "0" ]; then
        _mbf_log "$@"
    else
        _mbf_log "$@" >&2
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
