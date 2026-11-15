#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use config exec

function test_php_ini_and_special_characters_mutations() {
    local php_ini
    mbf::exec::tmpfile php_ini
    mbf::config::insert "$php_ini" "memory_limit = 512M"
    mbf::config::insert "$php_ini" "sendmail_path = /usr/sbin/sendmail"
    mbf::config::insert "$php_ini" "webhook_url = https://old.example.com/hook"

    # Update keys including slashes, `&` query params, and `|` pipes
    mbf::config::set "$php_ini" "memory_limit" "4G"
    mbf::config::set "$php_ini" "sendmail_path" "/usr/local/bin/mhsendmail"
    mbf::config::set "$php_ini" "webhook_url" "https://saas.example.com/hook?env=prod&notify=slack|tg"
    mbf::config::set "$php_ini" "opcache.memory_consumption" "512"

    assert_eq "4G" "$(mbf::config::get "$php_ini" "memory_limit")"
    assert_eq "/usr/local/bin/mhsendmail" "$(mbf::config::get "$php_ini" "sendmail_path")"
    assert_eq "https://saas.example.com/hook?env=prod&notify=slack|tg" "$(mbf::config::get "$php_ini" "webhook_url")"
    assert_eq "512" "$(mbf::config::get "$php_ini" "opcache.memory_consumption")"

    mbf::config::replace_text "$php_ini" "env=prod&notify=slack|tg" "env=staging&notify=email"
    assert_eq "https://saas.example.com/hook?env=staging&notify=email" "$(mbf::config::get "$php_ini" "webhook_url")"
}

function test_hosts_file_idempotent_line_and_block_management() {
    local hosts_file
    mbf::exec::tmpfile hosts_file
    printf '127.0.0.1 localhost\n' > "$hosts_file"

    mbf::config::ensure "$hosts_file" "127.0.0.1 magento.local"
    mbf::config::ensure "$hosts_file" "127.0.0.1 magento.local"
    assert_eq "1" "$(grep -c "127.0.0.1 magento.local" "$hosts_file")"

    mbf::config::ensure_block "$hosts_file" "docker_stack" $'172.20.0.10 mysql.internal\n172.20.0.11 redis.internal'
    mbf::config::ensure_block "$hosts_file" "docker_stack" $'172.20.0.10 mysql.internal\n172.20.0.20 opensearch.internal'

    assert_eq "1" "$(grep -c "# BEGIN MBF:docker_stack" "$hosts_file")"
    assert_contains "$(cat "$hosts_file")" "172.20.0.20 opensearch.internal"
    assert_not_contains "$(cat "$hosts_file")" "172.20.0.11 redis.internal"
}

function test_backup_rollback_and_line_operations() {
    local conf
    mbf::exec::tmpfile conf
    printf 'MAGENTO_MODE=production\nVARNISH_PORT=6081\n' > "$conf"

    mbf::config::backup "$conf"
    mbf::config::replace_line "$conf" "MAGENTO_MODE" "MAGENTO_MODE=developer"
    assert_contains "$(cat "$conf")" "MAGENTO_MODE=developer"

    mbf::config::rollback "$conf" 2>/dev/null
    assert_contains "$(cat "$conf")" "MAGENTO_MODE=production"

    local ln
    ln="$(mbf::config::line_number "$conf" "VARNISH_PORT=6081")"
    assert_eq "2" "$ln"
    mbf::config::append_after_line "$conf" "$ln" "REDIS_HOST=127.0.0.1"
    assert_eq "3" "$(mbf::config::line_number "$conf" "REDIS_HOST=127.0.0.1")"
}

run_test_suite "Config File Manipulation & Backup (mbf::config::*)"
