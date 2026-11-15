#!/usr/bin/env bash
# @mbf-module: args
# @mbf-rank: ••••
# mbf:requires log
# ==============================================================================
# mbf core library: args
# Declarative CLI flag & option parser and automatic --help generator
#
# Internal Registry Format (`MBF_ARG_DEFS`):
#   Each registered flag/option appends one pipe-delimited line:
#   `kind|short|long|var_name|description|default_value`
#   where `kind` is either `flag` (boolean 0/1) or `opt` (takes a `<val>`).
# ==============================================================================

# mbf:state_start
MBF_ARG_DEFS=""
MBF_POSITIONAL_ARGS=()
USAGE="${USAGE:-}"
# mbf:state_end

# Register a boolean CLI flag (initializes target variable to "0" if unset)
# Usage: mbf::args::flag "v" "verbose" "OPT_VERBOSE" "Enable verbose output"
function mbf::args::flag() {
    local short="$1"
    local long="$2"
    local var_name="$3"
    local desc="$4"
    # `${!var_name:-0}` reads the current value of variable `$var_name` indirectly;
    # `printf -v "$var_name"` assigns to `$var_name` without `eval`.
    printf -v "$var_name" '%s' "${!var_name:-0}"
    MBF_ARG_DEFS="${MBF_ARG_DEFS}flag|${short}|${long}|${var_name}|${desc}|0"$'\n'
}

# Register a key-value CLI option with optional default value
# Usage: mbf::args::option "e" "env" "OPT_ENV" "Target environment" "dev"
function mbf::args::option() {
    local short="$1"
    local long="$2"
    local var_name="$3"
    local desc="$4"
    local default_val="${5:-}"
    if [ -z "${!var_name:-}" ] && [ -n "$default_val" ]; then
        printf -v "$var_name" '%s' "$default_val"
    fi
    MBF_ARG_DEFS="${MBF_ARG_DEFS}opt|${short}|${long}|${var_name}|${desc}|${default_val}"$'\n'
}

function _mbf_format_arg_help_line() {
    local kind="$1" short="$2" long="$3" desc="$4" def_val="$5"
    local flag_str=""

    if [ -n "$short" ] && [ -n "$long" ]; then
        flag_str="-${short}, --${long}"
    elif [ -n "$short" ]; then
        flag_str="-${short}"
    else
        flag_str="    --${long}"
    fi

    [ "$kind" == "opt" ] && flag_str="${flag_str} <val>"

    if [ -n "$def_val" ] && [ "$kind" == "opt" ]; then
        printf '  %-25s %s (default: %s)\n' "$flag_str" "$desc" "$def_val"
    else
        printf '  %-25s %s\n' "$flag_str" "$desc"
    fi
}

# Print formatted help message from USAGE and registered flags/options
function mbf::args::help() {
    if [ -n "${USAGE:-}" ]; then
        printf '%s\n\n' "$USAGE"
    else
        printf 'Usage: %s [options]\n\n' "$(basename "${0:-script.sh}")"
    fi

    printf 'Options:\n'
    printf '  -h, --help                Show this help message and exit\n'

    if [ -n "${MBF_ARG_DEFS:-}" ]; then
        local kind short long var_name desc def_val
        while IFS='|' read -r kind short long var_name desc def_val; do
            [ -z "$kind" ] && continue
            _mbf_format_arg_help_line "$kind" "$short" "$long" "$desc" "$def_val"
        done <<< "$MBF_ARG_DEFS"
    fi
}

# Internal helper: Match current CLI argument against registered definitions.
# Sets `_MBF_ARGS_SHIFT` to the number of arguments consumed (1 or 2),
# or returns 1 if unregistered, or returns 2 if a required option value is missing.
function _mbf_args_match_def() {
    local arg="$1"
    local has_next="$2"
    local next_val="$3"
    _MBF_ARGS_SHIFT=0

    [ -z "${MBF_ARG_DEFS:-}" ] && return 1

    local kind short long var_name desc def_val
    while IFS='|' read -r kind short long var_name desc def_val; do
        [ -z "$kind" ] && continue
        if [ "$arg" == "-${short}" ] || [ "$arg" == "--${long}" ]; then
            if [ "$kind" == "flag" ]; then
                printf -v "$var_name" '%s' "1"
                _MBF_ARGS_SHIFT=1
                return 0
            fi
            if [ "$has_next" -eq 0 ]; then
                return 2
            fi
            printf -v "$var_name" '%s' "$next_val"
            _MBF_ARGS_SHIFT=2
            return 0
        elif [[ "$kind" == "opt" && "$arg" == "--${long}="* ]]; then
            printf -v "$var_name" '%s' "${arg#*=}"
            _MBF_ARGS_SHIFT=1
            return 0
        fi
    done <<< "$MBF_ARG_DEFS"

    return 1
}

# Parse command-line arguments against registered flags and options
# Populates registered option variables and stores remaining args in MBF_POSITIONAL_ARGS.
# Usage: mbf::args::parse "$@"
function mbf::args::parse() {
    MBF_POSITIONAL_ARGS=()
    local _MBF_ARGS_SHIFT=0

    while [ $# -gt 0 ]; do
        local arg="$1"
        if [ "$arg" == "-h" ] || [ "$arg" == "--help" ]; then
            mbf::args::help
            return 0
        fi

        local has_next=0 next_val="" rc=0
        if [ $# -ge 2 ]; then
            has_next=1
            next_val="$2"
        fi

        _mbf_args_match_def "$arg" "$has_next" "$next_val" || rc=$?
        if [ "$rc" -eq 0 ]; then
            shift "$_MBF_ARGS_SHIFT"
            continue
        elif [ "$rc" -eq 2 ]; then
            mbf::log::error "Option '$arg' requires a value."
            mbf::args::help
            return 1
        fi

        if [[ "$arg" == -* ]]; then
            mbf::log::error "Unknown option '$arg'."
            mbf::args::help
            return 1
        else
            MBF_POSITIONAL_ARGS+=("$arg")
            shift 1
        fi
    done
    return 0
}
