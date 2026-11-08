#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf_use args

function setup() {
    MBF_ARG_DEFS=""
    MBF_POSITIONAL_ARGS=()
    unset OPT_VERBOSE OPT_ENV OPT_PORT
}

function test_declarative_flags_and_options() {
    mbf_arg_flag "v" "verbose" "OPT_VERBOSE" "Enable verbose mode"
    mbf_arg_option "e" "env" "OPT_ENV" "Target environment" "staging"
    mbf_arg_option "p" "port" "OPT_PORT" "Server port" "8080"

    assert_eq "0" "$OPT_VERBOSE"
    assert_eq "staging" "$OPT_ENV"
    assert_eq "8080" "$OPT_PORT"

    mbf_parse_args -v --env production --port=9090 deploy_target
    assert_eq "1" "$OPT_VERBOSE"
    assert_eq "production" "$OPT_ENV"
    assert_eq "9090" "$OPT_PORT"
    assert_eq "deploy_target" "${MBF_POSITIONAL_ARGS[0]}"
}

function test_help_generation() {
    USAGE="Usage: deploy.sh [options]"
    mbf_arg_flag "v" "verbose" "OPT_VERBOSE" "Enable verbose mode"
    mbf_arg_option "e" "env" "OPT_ENV" "Target environment" "dev"

    local help_out
    help_out="$(mbf_parse_args --help)"
    assert_contains "$help_out" "Usage: deploy.sh [options]"
    assert_contains "$help_out" "-v, --verbose"
    assert_contains "$help_out" "-e, --env <val>"
}

function test_legacy_params_compatibility() {
    PARAMS="v;verbose;Print output\ne;env;Environment name"
    process_params -v -e prod
    assert_eq "1" "${MBF_VERBOSE:-0}"
    assert_eq "prod" "${PARAM_e:-}"
}

run_test_suite "CLI Argument & Flag Parsing"
