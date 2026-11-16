#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use args

function test_deployment_cli_flags_options_and_double_dash() {
    mbf::args::flag "v" "verbose" "OPT_VERBOSE" "Enable verbose deployment logs (info|debug)"
    mbf::args::option "e" "env" "OPT_ENV" "Target deployment environment (dev|staging|prod)" "staging"
    mbf::args::option "d" "domain" "OPT_DOMAIN" "Storefront domain" "staging.shop.example.com"
    mbf::args::option "w" "workers" "OPT_WORKERS" "Static content deploy workers" "4"

    assert_eq "0" "$OPT_VERBOSE"
    assert_eq "staging" "$OPT_ENV"
    assert_eq "staging.shop.example.com" "$OPT_DOMAIN"
    assert_eq "4" "$OPT_WORKERS"

    mbf::args::parse -v --env production --domain=shop.example.com --workers 8 -- --literal-arg release_v2
    assert_eq "1" "$OPT_VERBOSE"
    assert_eq "production" "$OPT_ENV"
    assert_eq "shop.example.com" "$OPT_DOMAIN"
    assert_eq "8" "$OPT_WORKERS"
    assert_eq "--literal-arg" "${MBF_POSITIONAL_ARGS[0]}"
    assert_eq "release_v2" "${MBF_POSITIONAL_ARGS[1]}"
}

function test_help_exit_and_error_cases() {
    USAGE="Usage: deploy-magento.sh [options] <release_tag>"
    mbf::args::flag "v" "verbose" "OPT_VERBOSE" "Enable verbose deployment logs (info|debug)"
    mbf::args::option "e" "env" "OPT_ENV" "Target environment" "staging"

    # Regression B10: `--help` prints help and terminates the subshell with exit code 0
    local help_out
    help_out="$(mbf::args::parse --help; echo "SHOULD_NOT_RUN")"
    assert_contains "$help_out" "Usage: deploy-magento.sh [options] <release_tag>"
    assert_contains "$help_out" "-v, --verbose"
    assert_contains "$help_out" "(info|debug)"
    assert_contains "$help_out" "-e, --env <val>"
    assert_not_contains "$help_out" "SHOULD_NOT_RUN"

    local direct_help
    direct_help="$(mbf::args::help)"
    assert_contains "$direct_help" "Options:"

    local rc=0
    mbf::args::parse --unknown-option >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc"

    rc=0
    mbf::args::parse --env >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "Missing value for option should return 1"
}

run_test_suite "CLI Argument & Flag Parsing (mbf::args::*)"
