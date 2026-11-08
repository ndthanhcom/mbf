#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf_use config

TEST_CONF=""

function setup() {
    TEST_CONF="$(mktemp "${TMPDIR:-/tmp}/mbf.conf.XXXXXX")"
}

function teardown() {
    rm -f "$TEST_CONF"
}

function test_insert_and_get_config() {
    insert_config "$TEST_CONF" "127.0.0.1 = ndthanh.net" >/dev/null
    insert_config "$TEST_CONF" "memory_limit = 4G" >/dev/null

    assert_eq "ndthanh.net" "$(get_config_value "$TEST_CONF" "127.0.0.1")"
    assert_eq "4G" "$(get_config_value "$TEST_CONF" "memory_limit")"
}

function test_ensure_config_idempotency() {
    ensure_config "$TEST_CONF" "app_env = production" >/dev/null
    ensure_config "$TEST_CONF" "app_env = production" >/dev/null

    local count
    count="$(grep -c "app_env = production" "$TEST_CONF")"
    assert_eq "1" "$count" "ensure_config should not duplicate existing lines"
}

function test_modify_config_value_including_slashes() {
    insert_config "$TEST_CONF" "127.0.0.1 = ndthanh.net" >/dev/null
    insert_config "$TEST_CONF" "sendmail_path = /usr/sbin/sendmail" >/dev/null

    modify_config_value "$TEST_CONF" "127.0.0.1" "isevenr.com" >/dev/null
    modify_config_value "$TEST_CONF" "sendmail_path" "/usr/local/bin/mhsendmail" >/dev/null

    assert_eq "isevenr.com" "$(get_config_value "$TEST_CONF" "127.0.0.1")"
    assert_eq "/usr/local/bin/mhsendmail" "$(get_config_value "$TEST_CONF" "sendmail_path")"
}

function test_delete_and_replace_line() {
    insert_config "$TEST_CONF" "memory_limit = 4G" >/dev/null
    insert_config "$TEST_CONF" "default_socket_timeout = 32" >/dev/null

    delete_line "$TEST_CONF" "memory_limit" >/dev/null
    assert_eq "no" "$(in_file "$TEST_CONF" "memory_limit")"

    replace_line "$TEST_CONF" "default_socket_timeout" "default_socket_timeout = 64" >/dev/null
    assert_eq "64" "$(get_config_value "$TEST_CONF" "default_socket_timeout")"
}

function test_replace_text_and_linenumber() {
    insert_config "$TEST_CONF" "aa bb cc" >/dev/null
    insert_config "$TEST_CONF" "SENDMAIL_PATH=/usr/local/bin/mhsendmail" >/dev/null

    replace_text_in_file "$TEST_CONF" "bb" "ee" >/dev/null
    assert_eq "yes" "$(in_file "$TEST_CONF" "aa ee cc")"

    local ln
    ln="$(get_text_linenumber "$TEST_CONF" "SENDMAIL_PATH=/usr/local/bin/mhsendmail")"
    assert_eq "2" "$ln"

    append_after_linenumber "$TEST_CONF" 2 "APP_MODE=developer" >/dev/null
    assert_eq "3" "$(get_text_linenumber "$TEST_CONF" "APP_MODE=developer")"
}

run_test_suite "Config Manipulation"
