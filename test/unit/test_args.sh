#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use args

function test_declarative_flags_and_options() {
    mbf::args::flag "v" "verbose" "OPT_VERBOSE" "Enable verbose mode"
    mbf::args::option "e" "env" "OPT_ENV" "Target environment" "staging"
    mbf::args::option "p" "port" "OPT_PORT" "Server port" "8080"

    assert_eq "0" "$OPT_VERBOSE"
    assert_eq "staging" "$OPT_ENV"
    assert_eq "8080" "$OPT_PORT"

    mbf::args::parse -v --env production --port=9090 deploy_target
    assert_eq "1" "$OPT_VERBOSE"
    assert_eq "production" "$OPT_ENV"
    assert_eq "9090" "$OPT_PORT"
    assert_eq "deploy_target" "${MBF_POSITIONAL_ARGS[0]}"
}

function test_help_generation_and_unknown_flag() {
    USAGE="Usage: deploy.sh [options]"
    mbf::args::flag "v" "verbose" "OPT_VERBOSE" "Enable verbose mode"
    mbf::args::option "e" "env" "OPT_ENV" "Target environment" "dev"

    local help_out
    help_out="$(mbf::args::parse --help)"
    assert_contains "$help_out" "Usage: deploy.sh [options]"
    assert_contains "$help_out" "-v, --verbose"
    assert_contains "$help_out" "-e, --env <val>"

    mbf::args::parse --invalid-flag >/dev/null 2>&1
    assert_eq "1" "$?"
}

run_test_suite "CLI Argument & Flag Parsing (mbf::args::*)"
