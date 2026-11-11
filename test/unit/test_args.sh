#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use args

function test_deployment_cli_flags_and_options() {
    mbf::args::flag "v" "verbose" "OPT_VERBOSE" "Enable verbose deployment logs"
    mbf::args::option "e" "env" "OPT_ENV" "Target deployment environment" "staging"
    mbf::args::option "d" "domain" "OPT_DOMAIN" "Storefront domain" "staging.shop.example.com"
    mbf::args::option "w" "workers" "OPT_WORKERS" "Static content deploy workers" "4"

    assert_eq "0" "$OPT_VERBOSE"
    assert_eq "staging" "$OPT_ENV"
    assert_eq "staging.shop.example.com" "$OPT_DOMAIN"
    assert_eq "4" "$OPT_WORKERS"

    mbf::args::parse -v --env production --domain=shop.example.com --workers 8 release_v2
    assert_eq "1" "$OPT_VERBOSE"
    assert_eq "production" "$OPT_ENV"
    assert_eq "shop.example.com" "$OPT_DOMAIN"
    assert_eq "8" "$OPT_WORKERS"
    assert_eq "release_v2" "${MBF_POSITIONAL_ARGS[0]}"
}

function test_help_generation_and_unknown_flag() {
    USAGE="Usage: deploy-magento.sh [options] <release_tag>"
    mbf::args::flag "v" "verbose" "OPT_VERBOSE" "Enable verbose deployment logs"
    mbf::args::option "e" "env" "OPT_ENV" "Target environment" "staging"

    local help_out
    help_out="$(mbf::args::parse --help)"
    assert_contains "$help_out" "Usage: deploy-magento.sh [options] <release_tag>"
    assert_contains "$help_out" "-v, --verbose"
    assert_contains "$help_out" "-e, --env <val>"

    mbf::args::parse --unknown-option >/dev/null 2>&1
    assert_eq "1" "$?"
}

run_test_suite "CLI Argument & Flag Parsing (mbf::args::*)"
