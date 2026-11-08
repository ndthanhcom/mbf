#!/usr/bin/env bash
# ==============================================================================
# mbf module: args (also aliased as parameters)
# Declarative CLI flag & option parser and help generator
# ==============================================================================

MBF_ARG_DEFS=""
MBF_POSITIONAL_ARGS=()

# Register a boolean CLI flag
# Usage: mbf_arg_flag "v" "verbose" "VERBOSE" "Enable verbose output"
function mbf_arg_flag() {
    local short="$1"
    local long="$2"
    local var_name="$3"
    local desc="$4"
    printf -v "$var_name" '%s' "${!var_name:-0}"
    MBF_ARG_DEFS="${MBF_ARG_DEFS}flag|${short}|${long}|${var_name}|${desc}|0"$'\n'
}

# Register a key-value CLI option
# Usage: mbf_arg_option "e" "env" "TARGET_ENV" "Target environment" "dev"
function mbf_arg_option() {
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

# Internal helper: format a single option line for print_help
function _mbf_format_arg_help_line() {
    local kind="$1"
    local short="$2"
    local long="$3"
    local desc="$4"
    local def_val="$5"
    local flag_str=""

    if [ -n "$short" ] && [ -n "$long" ]; then
        flag_str="-${short}, --${long}"
    elif [ -n "$short" ]; then
        flag_str="-${short}"
    else
        flag_str="    --${long}"
    fi

    if [ "$kind" == "opt" ]; then
        flag_str="${flag_str} <val>"
    fi

    if [ -n "$def_val" ] && [ "$kind" == "opt" ]; then
        printf '  %-25s %s (default: %s)\n' "$flag_str" "$desc" "$def_val"
    else
        printf '  %-25s %s\n' "$flag_str" "$desc"
    fi
}

# Print formatted help message from USAGE and registered options/PARAMS
function print_help() {
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

    if [ -n "${PARAMS:-}" ]; then
        local line s l d
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            IFS=';' read -r s l d <<< "$line"
            [ -z "$s" ] && [ -z "$l" ] && continue
            printf '  -%s, --%-19s %s\n' "$s" "$l" "$d"
        done < <(printf '%b\n' "$PARAMS")
    fi
}

# Parse command line arguments against registered mbf_arg_flag / mbf_arg_option definitions
# Usage: mbf_parse_args "$@"
function mbf_parse_args() {
    MBF_POSITIONAL_ARGS=()

    while [ $# -gt 0 ]; do
        local arg="$1"
        if [ "$arg" == "-h" ] || [ "$arg" == "--help" ]; then
            print_help
            return 0
        fi

        local matched=0
        if [ -n "${MBF_ARG_DEFS:-}" ]; then
            local kind short long var_name desc def_val
            while IFS='|' read -r kind short long var_name desc def_val; do
                [ -z "$kind" ] && continue
                if [ "$arg" == "-${short}" ] || [ "$arg" == "--${long}" ]; then
                    matched=1
                    if [ "$kind" == "flag" ]; then
                        printf -v "$var_name" '%s' "1"
                        shift 1
                    else
                        if [ $# -lt 2 ]; then
                            print_with_color "Option '$arg' requires a value." red
                            print_help
                            return 1
                        fi
                        printf -v "$var_name" '%s' "$2"
                        shift 2
                    fi
                    break
                elif [[ "$kind" == "opt" && "$arg" == "--${long}="* ]]; then
                    matched=1
                    printf -v "$var_name" '%s' "${arg#*=}"
                    shift 1
                    break
                fi
            done <<< "$MBF_ARG_DEFS"
        fi

        if [ "$matched" -eq 1 ]; then
            continue
        fi

        if [[ "$arg" == -* ]]; then
            print_with_color "Invalid parameter '$arg'." red
            print_help
            return 1
        else
            MBF_POSITIONAL_ARGS+=("$arg")
            shift 1
        fi
    done
    return 0
}

# Legacy compatibility with parameters.sh PARAMS string ("short;long;description")
function process_param() {
    local pname="$1"
    local next_val="${2:-}"
    local params_list="${PARAMS:-v;verbose;Print output to terminal to see what is happening}"
    local line s l d

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        IFS=';' read -r s l d <<< "$line"
        if [ "$pname" == "-${s}" ] || [ "$pname" == "--${l}" ]; then
            if [ "$s" == "v" ] || [ "$l" == "verbose" ]; then
                MBF_VERBOSE=1
                printf '1'
                return 0
            fi
            if [ -n "$next_val" ] && [[ "$next_val" != -* ]]; then
                printf '2'
                return 0
            fi
            printf '1'
            return 0
        fi
    done < <(printf '%b\n' "$params_list")

    printf '0'
}

function process_params() {
    while [ $# -gt 0 ]; do
        if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
            print_help
            return 0
        fi
        local shift_step
        shift_step="$(process_param "$1" "${2:-}")"
        if [ "$shift_step" == "0" ]; then
            if function_exists print_with_color; then
                print_with_color "Invalid parameter '$1'. \n ### PLEASE SEE HELP CONTENT BELOW FOR MORE INFORMATION. ###\n" red
            fi
            print_help
            return 1
        else
            local var_key="${1#-}"
            var_key="${var_key#-}"
            var_key="${var_key//-/_}"
            if [ "$var_key" == "v" ] || [ "$var_key" == "verbose" ]; then
                MBF_VERBOSE=1
            fi
            if [ "$shift_step" == "2" ]; then
                printf -v "PARAM_${var_key}" '%s' "$2"
            else
                printf -v "PARAM_${var_key}" '%s' "1"
            fi
            shift "$shift_step"
        fi
    done
}
