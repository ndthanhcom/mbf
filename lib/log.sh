#!/usr/bin/env bash
# ==============================================================================
# mbf module: log
# Logging, debugger trace, and /tmp log file monitoring
#
# Environment Variables:
#   MBF_LOG       : Set to "1" (or I7R_LOGGING="1") to append logs/errors to MBF_LOG_FILE
#   MBF_LOG_FILE  : Log file path when MBF_LOG=1 (default: /tmp/mbf.log)
#   MBF_DEBUG     : Set to "1" to enable debug messages and caller stack traces
#   NO_COLOR      : Set to non-empty to disable ANSI terminal colors
# ==============================================================================

PRINTF="${PRINTF:-$(command -v printf)}"
MBF_LOG_FILE="${MBF_LOG_FILE:-/tmp/mbf.log}"

# Return 0 if file logging is enabled via MBF_LOG=1, I7R_LOGGING=1, or explicit MBF_LOG_ENABLE
function mbf_is_log_enabled() {
    [ "${MBF_LOG:-${I7R_LOGGING:-0}}" == "1" ]
}

# Return 0 if debug mode is enabled via MBF_DEBUG=1 or MBF_VERBOSE=1
function mbf_is_debug_enabled() {
    [ "${MBF_DEBUG:-${MBF_VERBOSE:-0}}" == "1" ]
}

# Map color name to ANSI escape sequence
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

# Append a plain-text timestamped entry to MBF_LOG_FILE (/tmp/mbf.log by default)
# Usage: mbf_write_log "ERROR" "message"
function mbf_write_log() {
    local level="$1"
    shift
    local message="$*"
    local target_file="${MBF_LOG_FILE:-/tmp/mbf.log}"
    local timestamp
    timestamp="$(date +'%Y-%m-%d / T%H:%M:%S%z')"

    mkdir -p "$(dirname "$target_file")" 2>/dev/null || true
    $PRINTF "%s [%s] %b\n" "$timestamp" "$level" "$message" >> "$target_file"
}

# Print string with color and timestamp; writes to MBF_LOG_FILE when MBF_LOG=1
# Usage: print_with_color "message to print" [color]
function print_with_color() {
    local message="$1"
    local color="${2:-yellow}"
    local timestamp
    timestamp="$(date +'%Y-%m-%d / T%H:%M:%S%z')"

    if [ -n "${NO_COLOR:-}" ]; then
        $PRINTF "%s %b\n" "$timestamp" "$message"
    else
        local active_color
        active_color="$(_mbf_color_code "$color")"
        local time_color='\033[0;34m'
        local color_reset='\033[0m'
        $PRINTF "${time_color}%s ${active_color}%b${color_reset}\n" "$timestamp" "$message"
    fi

    if mbf_is_log_enabled; then
        mbf_write_log "LOG" "$message"
    fi
}

# Print step in pre-formatted template
function print_step_msg() {
    local message="$1"
    local color="${2:-cyan}"
    print_with_color "[ $message ]" "$color"
}

function log_info() {
    print_with_color "[INFO] $*" "cyan"
}

function log_success() {
    print_with_color "[OK] $*" "green"
}

function log_warn() {
    print_with_color "[WARN] $*" "yellow" >&2
}

# Log an error to stderr, always record in MBF_LOG_FILE if MBF_LOG=1 or MBF_DEBUG=1,
# and print caller stack trace when MBF_DEBUG=1
function log_error() {
    local msg="$*"
    print_with_color "[ERROR] $msg" "red" >&2

    # If MBF_DEBUG=1 (even if MBF_LOG=0), also append errors to MBF_LOG_FILE for monitoring
    if ! mbf_is_log_enabled && mbf_is_debug_enabled; then
        mbf_write_log "ERROR" "$msg"
    fi

    if mbf_is_debug_enabled; then
        mbf_debug_stack_trace >&2
    fi
}

# Print debug message with caller file:line context when MBF_DEBUG=1
function log_debug() {
    if mbf_is_debug_enabled; then
        local caller_src="${BASH_SOURCE[1]:-script}"
        local caller_line="${BASH_LINENO[0]:-0}"
        local caller_fn="${FUNCNAME[1]:-main}"
        local loc
        loc="$(basename "$caller_src"):${caller_line}:${caller_fn}"
        print_with_color "[DEBUG] (${loc}) $*" "purple" >&2

        if ! mbf_is_log_enabled; then
            mbf_write_log "DEBUG" "(${loc}) $*"
        fi
    fi
}

# Print current bash call stack (useful for debugging failed commands or traps)
function mbf_debug_stack_trace() {
    local i
    local depth="${#FUNCNAME[@]}"
    $PRINTF "  Stack trace:\n"
    for ((i = 1; i < depth; i++)); do
        local fn="${FUNCNAME[$i]:-main}"
        local src="${BASH_SOURCE[$i]:-unknown}"
        local line="${BASH_LINENO[$((i - 1))]:-0}"
        $PRINTF "    at %s (%s:%s)\n" "$fn" "$src" "$line"
    done
}

# Enable or disable verbose bash xtrace (set -x) redirected to stderr / log
function mbf_enable_xtrace() {
    export PS4='+(${BASH_SOURCE##*/}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -x
}

function mbf_disable_xtrace() {
    set +x
}

function die() {
    log_error "$*"
    exit 1
}
