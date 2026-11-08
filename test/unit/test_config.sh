#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use config fs

function test_insert_and_get_config() {
    local conf
    mbf::fs::tmpfile conf
    mbf::config::insert "$conf" "127.0.0.1 = ndthanh.net"
    mbf::config::insert "$conf" "memory_limit = 4G"

    assert_eq "ndthanh.net" "$(mbf::config::get "$conf" "127.0.0.1")"
    assert_eq "4G" "$(mbf::config::get "$conf" "memory_limit")"
}

function test_ensure_config_idempotency() {
    local conf
    mbf::fs::tmpfile conf
    mbf::config::ensure "$conf" "app_env = production"
    mbf::config::ensure "$conf" "app_env = production"

    assert_eq "1" "$(grep -c "app_env = production" "$conf")"
}

function test_set_config_including_slashes() {
    local conf
    mbf::fs::tmpfile conf
    mbf::config::insert "$conf" "127.0.0.1 = ndthanh.net"
    mbf::config::insert "$conf" "sendmail_path = /usr/sbin/sendmail"

    mbf::config::set "$conf" "127.0.0.1" "isevenr.com"
    mbf::config::set "$conf" "sendmail_path" "/usr/local/bin/mhsendmail"

    assert_eq "isevenr.com" "$(mbf::config::get "$conf" "127.0.0.1")"
    assert_eq "/usr/local/bin/mhsendmail" "$(mbf::config::get "$conf" "sendmail_path")"
}

function test_delete_and_replace_line() {
    local conf
    mbf::fs::tmpfile conf
    mbf::config::insert "$conf" "memory_limit = 4G"
    mbf::config::insert "$conf" "default_socket_timeout = 32"

    mbf::config::delete_line "$conf" "memory_limit"
    assert_eq "1" "$(mbf::in_file "$conf" "memory_limit" && echo 0 || echo 1)"

    mbf::config::replace_line "$conf" "default_socket_timeout" "default_socket_timeout = 64"
    assert_eq "64" "$(mbf::config::get "$conf" "default_socket_timeout")"
}

function test_replace_text_and_line_number() {
    local conf
    mbf::fs::tmpfile conf
    mbf::config::insert "$conf" "aa bb cc"
    mbf::config::insert "$conf" "SENDMAIL_PATH=/usr/local/bin/mhsendmail"

    mbf::config::replace_text "$conf" "bb" "ee"
    assert_eq "0" "$(mbf::in_file "$conf" "aa ee cc" && echo 0 || echo 1)"

    local ln
    ln="$(mbf::config::line_number "$conf" "SENDMAIL_PATH=/usr/local/bin/mhsendmail")"
    assert_eq "2" "$ln"

    mbf::config::append_after_line "$conf" 2 "APP_MODE=developer"
    assert_eq "3" "$(mbf::config::line_number "$conf" "APP_MODE=developer")"

    mbf::config::line_number "$conf" "NONEXISTENT_KEY_XYZ" >/dev/null 2>&1
    assert_eq "1" "$?"
}

run_test_suite "Config Manipulation (mbf::config::*)"
