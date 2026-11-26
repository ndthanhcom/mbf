#!/usr/bin/env bash
# @mbf-module: args
# mbf:requires log
# ==============================================================================
# mbf core library: args
# Declarative CLI flag & option parser and automatic --help generator
#
# Internal Registry Format (`MBF_ARG_DEFS`):
#   Each registered flag/option appends one line of 7 fields separated by the
#   ASCII "unit separator" (`$'\x1f'`), so descriptions may contain `|`, `:` etc.:
#   `kind short long var_name description default_value env_var`
#   where `kind` is `flag` (boolean 0/1), `opt` (single `<val>`), or `multi` (repeatable array).
#
# `-h` / `--help` behaviour:
#   Prints help and exits 0 (an intentional terminal action, like `mbf::die`).
#   Set MBF_ARGS_NO_EXIT=1 to make `mbf::args::parse` return 0 instead (legacy).
# ==============================================================================

# mbf:state_start
MBF_ARG_DEFS=""
MBF_CMD_DEFS=""
MBF_POSITIONAL_ARGS=()
MBF_USAGE="${MBF_USAGE:-}"
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

# Reset registered flags, options, subcommands, and positional args (for per-subcommand parsing)
# Usage: mbf::args::reset ["Usage: myctl deploy [options]"]
function mbf::args::reset() {
    MBF_ARG_DEFS=""
    MBF_CMD_DEFS=""
    MBF_POSITIONAL_ARGS=()
    MBF_USAGE="${1:-}"
    USAGE=""
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
    MBF_ARG_DEFS="${MBF_ARG_DEFS}flag${s}${short}${s}${long}${s}${var_name}${s}${desc}${s}0${s}"$'\n'
}

# Register a key-value CLI option with optional default value and env-var fallback
# Usage: mbf::args::option "e" "env" "OPT_ENV" "Target environment" "dev" [APP_ENV]
function mbf::args::option() {
    local short="$1" long="$2" var_name="$3" desc="$4" default_val="${5:-}" env_var="${6:-}"
    local s="$_MBF_ARGS_SEP"
    if [ -z "${!var_name:-}" ]; then
        if [ -n "$env_var" ] && [ -n "${!env_var:-}" ]; then
            printf -v "$var_name" '%s' "${!env_var}"
        elif [ -n "$default_val" ]; then
            printf -v "$var_name" '%s' "$default_val"
        fi
    fi
    MBF_ARG_DEFS="${MBF_ARG_DEFS}opt${s}${short}${s}${long}${s}${var_name}${s}${desc}${s}${default_val}${s}${env_var}"$'\n'
}

# Register a repeatable key-value CLI option that appends each value into a Bash array
# Usage: mbf::args::multi "H" "host" "OPT_HOSTS" "Target host (may be repeated)"
function mbf::args::multi() {
    local short="$1" long="$2" var_name="$3" desc="$4"
    local s="$_MBF_ARGS_SEP"
    if ! declare -p "$var_name" >/dev/null 2>&1; then
        declare -ga "${var_name}=()"
    fi
    MBF_ARG_DEFS="${MBF_ARG_DEFS}multi${s}${short}${s}${long}${s}${var_name}${s}${desc}${s}${s}"$'\n'
}

function _mbf_format_arg_help_line() {
    local kind="$1" short="$2" long="$3" desc="$4" def_val="$5" env_var="${6:-}"
    local flag_str extra=""

    if [ -n "$short" ] && [ -n "$long" ]; then
        flag_str="-${short}, --${long}"
    elif [ -n "$short" ]; then
        flag_str="-${short}"
    else
        flag_str="    --${long}"
    fi

    if [ "$kind" == "opt" ] || [ "$kind" == "multi" ]; then
        flag_str="${flag_str} <val>"
    fi

    if [ "$kind" == "opt" ] && [ -n "$def_val" ]; then
        extra="${extra} (default: ${def_val})"
    elif [ "$kind" == "multi" ]; then
        extra="${extra} (repeatable)"
    fi
    if [ -n "$env_var" ]; then
        extra="${extra} [env: ${env_var}]"
    fi

    printf '  %-25s %s%s\n' "$flag_str" "$desc" "$extra"
}

# Print formatted help message from MBF_USAGE/USAGE and registered flags/options
function mbf::args::help() {
    local usage_text="${MBF_USAGE:-${USAGE:-}}"
    if [ -n "$usage_text" ]; then
        printf '%s\n\n' "$usage_text"
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

    local kind short long var_name desc def_val env_var
    while IFS="$_MBF_ARGS_SEP" read -r kind short long var_name desc def_val env_var; do
        [ -n "$kind" ] || continue
        _mbf_format_arg_help_line "$kind" "$short" "$long" "$desc" "$def_val" "$env_var"
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

    local kind short long var_name desc def_val env_var
    while IFS="$_MBF_ARGS_SEP" read -r kind short long var_name desc def_val env_var; do
        [ -n "$kind" ] || continue
        if { [ -n "$short" ] && [ "$arg" == "-${short}" ]; } || { [ -n "$long" ] && [ "$arg" == "--${long}" ]; }; then
            if [ "$kind" == "flag" ]; then
                printf -v "$var_name" '%s' "1"
                _MBF_ARGS_SHIFT=1
                return 0
            fi
            [ "$has_next" -eq 1 ] || return 2
            if [ "$kind" == "multi" ]; then
                local -n _mbf_multi_ref="$var_name"
                _mbf_multi_ref+=("$next_val")
            else
                printf -v "$var_name" '%s' "$next_val"
            fi
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
        elif [ "$kind" == "multi" ] && [ -n "$long" ] && [[ "$arg" == "--${long}="* ]]; then
            local -n _mbf_multi_eq_ref="$var_name"
            _mbf_multi_eq_ref+=("${arg#*=}")
            _MBF_ARGS_SHIFT=1
            return 0
        fi
    done <<< "${MBF_ARG_DEFS:-}"

    return 1
}

# Internal helper: expand a combined short-flag cluster (e.g. `-nv`) when every
# character is a registered boolean flag (or `h`). Returns 0 if matched, 3 if `-h`
# was present in the cluster, or 1 if any character is not a registered boolean flag.
function _mbf_args_match_short_cluster() {
    local cluster="${1#-}"
    local i ch len="${#cluster}" has_help=0
    local -a matched_vars=()

    for ((i = 0; i < len; i++)); do
        ch="${cluster:i:1}"
        if [ "$ch" == "h" ]; then
            has_help=1
            continue
        fi
        local kind short long var_name desc def_val env_var found=0
        while IFS="$_MBF_ARGS_SEP" read -r kind short long var_name desc def_val env_var; do
            if [ "$kind" == "flag" ] && [ "$short" == "$ch" ]; then
                matched_vars+=("$var_name")
                found=1
                break
            fi
        done <<< "${MBF_ARG_DEFS:-}"
        [ "$found" -eq 1 ] || return 1
    done

    [ "$has_help" -eq 1 ] && return 3

    local v
    for v in "${matched_vars[@]}"; do
        printf -v "$v" '%s' "1"
    done
    return 0
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

        if [[ "$arg" =~ ^-[a-zA-Z0-9]{2,}$ ]]; then
            local cl_rc=0
            _mbf_args_match_short_cluster "$arg" || cl_rc=$?
            if [ "$cl_rc" -eq 0 ]; then
                shift 1
                continue
            elif [ "$cl_rc" -eq 3 ]; then
                mbf::args::help
                [ "${MBF_ARGS_NO_EXIT:-0}" == "1" ] && return 0
                exit 0
            fi
        fi

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
