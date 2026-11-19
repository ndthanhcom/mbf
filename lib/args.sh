#!/usr/bin/env bash
# @mbf-module: args
# @mbf-rank: ••••
# mbf:requires log
# ==============================================================================
# mbf core library: args
# Declarative CLI flag & option parser and automatic --help generator
#
# Internal Registry Format (`MBF_ARG_DEFS`):
#   Each registered flag/option appends one line of 6 fields separated by the
#   ASCII "unit separator" (`$'\x1f'`), so descriptions may contain `|`, `:` etc.:
#   `kind short long var_name description default_value`
#   where `kind` is either `flag` (boolean 0/1) or `opt` (takes a `<val>`).
#
# `-h` / `--help` behaviour:
#   Prints help and exits 0 (an intentional terminal action, like `mbf::die`).
#   Set MBF_ARGS_NO_EXIT=1 to make `mbf::args::parse` return 0 instead (legacy).
# ==============================================================================

# mbf:state_start
MBF_ARG_DEFS=""
MBF_CMD_DEFS=""
MBF_POSITIONAL_ARGS=()
USAGE="${USAGE:-}"
_MBF_ARGS_SEP=$'\x1f'
# mbf:state_end

# Register a CLI subcommand for `mbf::args::dispatch` and `--help` output
# Usage: mbf::args::command "deploy" "Deploy application to target environment"
function mbf::args::command() {
    local name="$1" desc="$2"
    local s="$_MBF_ARGS_SEP"
    MBF_CMD_DEFS="${MBF_CMD_DEFS}${name}${s}${desc}"$'\n'
}

# Validate that one or more parsed option variables are set and non-empty
# Usage: mbf::args::require OPT_DOMAIN "domain (--domain)"
function mbf::args::require() {
    local var_name="${1:-}"
    local label="${2:-$var_name}"
    if [ -z "${!var_name:-}" ]; then
        mbf::log::error "Required option '${label}' is missing."
        mbf::args::help >&2
        return 1
    fi
    return 0
}

# Register a boolean CLI flag (initializes target variable to "0" if unset)
# Usage: mbf::args::flag "v" "verbose" "OPT_VERBOSE" "Enable verbose output"
function mbf::args::flag() {
    local short="$1" long="$2" var_name="$3" desc="$4"
    local s="$_MBF_ARGS_SEP"
    # `${!var_name:-0}` reads the current value of variable `$var_name` indirectly;
    # `printf -v "$var_name"` assigns to `$var_name` without `eval`.
    printf -v "$var_name" '%s' "${!var_name:-0}"
    MBF_ARG_DEFS="${MBF_ARG_DEFS}flag${s}${short}${s}${long}${s}${var_name}${s}${desc}${s}0"$'\n'
}

# Register a key-value CLI option with optional default value
# Usage: mbf::args::option "e" "env" "OPT_ENV" "Target environment" "dev"
function mbf::args::option() {
    local short="$1" long="$2" var_name="$3" desc="$4" default_val="${5:-}"
    local s="$_MBF_ARGS_SEP"
    if [ -z "${!var_name:-}" ] && [ -n "$default_val" ]; then
        printf -v "$var_name" '%s' "$default_val"
    fi
    MBF_ARG_DEFS="${MBF_ARG_DEFS}opt${s}${short}${s}${long}${s}${var_name}${s}${desc}${s}${default_val}"$'\n'
}

function _mbf_format_arg_help_line() {
    local kind="$1" short="$2" long="$3" desc="$4" def_val="$5"
    local flag_str

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

    if [ -n "${MBF_CMD_DEFS:-}" ]; then
        printf 'Commands:\n'
        local cmd_name cmd_desc
        while IFS="$_MBF_ARGS_SEP" read -r cmd_name cmd_desc; do
            [ -n "$cmd_name" ] || continue
            printf '  %-25s %s\n' "$cmd_name" "$cmd_desc"
        done <<< "${MBF_CMD_DEFS}"
        printf '\n'
    fi

    printf 'Options:\n'
    printf '  -h, --help                Show this help message and exit\n'

    local kind short long var_name desc def_val
    while IFS="$_MBF_ARGS_SEP" read -r kind short long var_name desc def_val; do
        [ -n "$kind" ] || continue
        _mbf_format_arg_help_line "$kind" "$short" "$long" "$desc" "$def_val"
    done <<< "${MBF_ARG_DEFS:-}"
}

# Internal helper: match one CLI argument against the registered definitions.
# Return codes: 0 = matched, 1 = not registered, 2 = option is missing its value.
# On success it sets `_MBF_ARGS_SHIFT` (1 or 2 = how many arguments were consumed).
# NOTE: `_MBF_ARGS_SHIFT` is declared `local` in `mbf::args::parse`; Bash's dynamic
# scoping lets this helper write to the caller's variable without a global.
function _mbf_args_match_def() {
    local arg="$1" has_next="$2" next_val="$3"
    _MBF_ARGS_SHIFT=0

    local kind short long var_name desc def_val
    while IFS="$_MBF_ARGS_SEP" read -r kind short long var_name desc def_val; do
        [ -n "$kind" ] || continue
        if { [ -n "$short" ] && [ "$arg" == "-${short}" ]; } || { [ -n "$long" ] && [ "$arg" == "--${long}" ]; }; then
            if [ "$kind" == "flag" ]; then
                printf -v "$var_name" '%s' "1"
                _MBF_ARGS_SHIFT=1
                return 0
            fi
            [ "$has_next" -eq 1 ] || return 2
            printf -v "$var_name" '%s' "$next_val"
            _MBF_ARGS_SHIFT=2
            return 0
        elif [ "$kind" == "flag" ] && [ -n "$long" ] && [ "$arg" == "--no-${long}" ]; then
            printf -v "$var_name" '%s' "0"
            _MBF_ARGS_SHIFT=1
            return 0
        elif [ "$kind" == "opt" ] && [ -n "$long" ] && [[ "$arg" == "--${long}="* ]]; then
            printf -v "$var_name" '%s' "${arg#*=}"
            _MBF_ARGS_SHIFT=1
            return 0
        fi
    done <<< "${MBF_ARG_DEFS:-}"

    return 1
}

# Parse command-line arguments against registered flags and options
# Populates registered option variables and stores remaining args in MBF_POSITIONAL_ARGS.
# Everything after a literal `--` is treated as positional.
# Usage: mbf::args::parse "$@"
function mbf::args::parse() {
    MBF_POSITIONAL_ARGS=()
    local _MBF_ARGS_SHIFT=0

    while [ $# -gt 0 ]; do
        local arg="$1"
        if [ "$arg" == "-h" ] || [ "$arg" == "--help" ]; then
            mbf::args::help
            [ "${MBF_ARGS_NO_EXIT:-0}" == "1" ] && return 0
            exit 0
        fi
        if [ "$arg" == "--" ]; then
            shift
            MBF_POSITIONAL_ARGS+=("$@")
            return 0
        fi

        local has_next=0 next_val="" rc=0
        if [ $# -ge 2 ]; then
            has_next=1
            next_val="$2"
        fi

        _mbf_args_match_def "$arg" "$has_next" "$next_val" || rc=$?
        case "$rc" in
            0)
                shift "$_MBF_ARGS_SHIFT"
                continue
                ;;
            2)
                mbf::log::error "Option '$arg' requires a value."
                mbf::args::help >&2
                return 1
                ;;
        esac

        if [[ "$arg" == -?* ]]; then
            mbf::log::error "Unknown option '$arg'."
            mbf::args::help >&2
            return 1
        fi
        MBF_POSITIONAL_ARGS+=("$arg")
        shift 1
    done
    return 0
}

# Dispatch a subcommand to `<fn_prefix>_<subcommand>` (registered via `mbf::args::command`)
# Usage: mbf::args::dispatch "cmd" "$@"
function mbf::args::dispatch() {
    local fn_prefix="${1:-}"
    shift 1 2>/dev/null || true
    local sub="${1:-}"

    if [ -z "$sub" ] || [ "$sub" == "-h" ] || [ "$sub" == "--help" ] || [ "$sub" == "help" ]; then
        mbf::args::help
        [ "${MBF_ARGS_NO_EXIT:-0}" == "1" ] && return 0
        exit 0
    fi
    shift 1

    local target_fn="${fn_prefix}_${sub//-/_}"
    if declare -F "$target_fn" >/dev/null 2>&1; then
        "$target_fn" "$@"
        return $?
    fi

    mbf::log::error "Unknown command '$sub'."
    mbf::args::help >&2
    return 1
}
