#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use config exec

function test_exact_key_matching_and_special_characters() {
    local php_ini
    mbf::exec::tmpfile php_ini
    printf 'export_port = 9200\nport = 3306\nmemory_limit = 512M\nsendmail_path = /usr/sbin/sendmail\n' > "$php_ini"
    mbf::config::insert "$php_ini" "webhook_url = https://old.example.com/hook"

    # Regression B2: setting `port` must NOT touch `export_port`
    mbf::config::set "$php_ini" "port" "3307"
    assert_eq "9200" "$(mbf::config::get "$php_ini" "export_port")"
    assert_eq "3307" "$(mbf::config::get "$php_ini" "port")"

    # Update keys including slashes, `&` query params, `|` pipes, and `\` backslashes
    mbf::config::set "$php_ini" "memory_limit" "4G"
    mbf::config::set "$php_ini" "sendmail_path" "/usr/local/bin/mhsendmail"
    mbf::config::set "$php_ini" "webhook_url" 'https://saas.example.com/hook?env=prod&notify=slack|tg\path'
    mbf::config::set "$php_ini" "opcache.memory_consumption" "512"

    assert_eq "4G" "$(mbf::config::get "$php_ini" "memory_limit")"
    assert_eq "/usr/local/bin/mhsendmail" "$(mbf::config::get "$php_ini" "sendmail_path")"
    assert_eq 'https://saas.example.com/hook?env=prod&notify=slack|tg\path' "$(mbf::config::get "$php_ini" "webhook_url")"
    assert_eq "512" "$(mbf::config::get "$php_ini" "opcache.memory_consumption")"

    mbf::config::replace_text "$php_ini" 'env=prod&notify=slack|tg\path' "env=staging&notify=email"
    assert_eq "https://saas.example.com/hook?env=staging&notify=email" "$(mbf::config::get "$php_ini" "webhook_url")"

    # Verify mbf::config::set preserves original `=` spacing (KEY=VAL vs KEY = VAL)
    local dotenv_sample
    mbf::exec::tmpfile dotenv_sample
    printf 'DB_HOST=127.0.0.1\nAPP_ENV = staging\n' > "$dotenv_sample"
    mbf::config::set "$dotenv_sample" "DB_HOST" "10.0.0.5"
    mbf::config::set "$dotenv_sample" "APP_ENV" "production"
    assert_contains "$(cat "$dotenv_sample")" "DB_HOST=10.0.0.5"
    assert_contains "$(cat "$dotenv_sample")" "APP_ENV = production"
}

function test_set_directive_ini_sections_and_dryrun_diff() {
    local sshd_conf ini_file
    mbf::exec::tmpfile sshd_conf
    mbf::exec::tmpfile ini_file

    # 1. set_directive: update existing, preserve indentation/semicolon, append missing
    cat <<'EOF' > "$sshd_conf"
# PermitRootLogin yes
PermitRootLogin yes
    worker_processes 2;
EOF
    mbf::config::set_directive "$sshd_conf" "PermitRootLogin" "no"
    mbf::config::set_directive "$sshd_conf" "worker_processes" "auto"
    mbf::config::set_directive "$sshd_conf" "PasswordAuthentication" "no"
    assert_eq "no" "$(mbf::config::get_directive "$sshd_conf" "PermitRootLogin")"
    assert_contains "$(cat "$sshd_conf")" "    worker_processes auto;"
    assert_eq "no" "$(mbf::config::get_directive "$sshd_conf" "PasswordAuthentication")"

    # 2. INI section-aware get/set
    cat <<'EOF' > "$ini_file"
[client]
port=3306

[mysqld]
port = 3306
max_connections = 100
EOF
    assert_eq "3306" "$(mbf::config::ini_get "$ini_file" "client" "port")"
    assert_eq "100"  "$(mbf::config::ini_get "$ini_file" "mysqld" "max_connections")"

    mbf::config::ini_set "$ini_file" "mysqld" "max_connections" "512"
    mbf::config::ini_set "$ini_file" "mysqld" "innodb_buffer_pool_size" "2G"
    mbf::config::ini_set "$ini_file" "client" "port" "3307"
    mbf::config::ini_set "$ini_file" "mysqldump" "quick" "true"

    assert_eq "3307" "$(mbf::config::ini_get "$ini_file" "client" "port")"
    assert_eq "3306" "$(mbf::config::ini_get "$ini_file" "mysqld" "port")"
    assert_eq "512"  "$(mbf::config::ini_get "$ini_file" "mysqld" "max_connections")"
    assert_eq "2G"   "$(mbf::config::ini_get "$ini_file" "mysqld" "innodb_buffer_pool_size")"
    assert_eq "true" "$(mbf::config::ini_get "$ini_file" "mysqldump" "quick")"
    assert_contains "$(cat "$ini_file")" "port=3307"

    # 3. Dry-run unified diff preview (emitted to stderr; file remains unchanged)
    local before diff_preview
    before="$(cat "$ini_file")"
    diff_preview="$(MBF_DRYRUN=1 NO_COLOR=1 mbf::config::ini_set "$ini_file" "mysqld" "max_connections" "999" 2>&1)"
    assert_eq "$before" "$(cat "$ini_file")" "Dry-run must not mutate config file"
    assert_contains "$diff_preview" "[DRYRUN]"
    if command -v diff >/dev/null 2>&1; then
        assert_contains "$diff_preview" "-max_connections = 512"
        assert_contains "$diff_preview" "+max_connections = 999"
    fi
}

function test_get_directive_and_idempotent_block_management() {
    local ssh_sample hosts_file
    mbf::exec::tmpfile ssh_sample
    mbf::exec::tmpfile hosts_file

    # First-match-wins semantics for space-separated directives (R4 / B13)
    cat <<'EOF' > "$ssh_sample"
# Commented PermitRootLogin yes
PermitRootLogin prohibit-password
PermitRootLogin yes
EOF
    assert_eq "prohibit-password" "$(mbf::config::get_directive "$ssh_sample" "PermitRootLogin")"

    printf '127.0.0.1 localhost\n# Footer line\n' > "$hosts_file"

    mbf::config::ensure "$hosts_file" "127.0.0.1 magento.local"
    mbf::config::ensure "$hosts_file" "127.0.0.1 magento.local"
    assert_eq "1" "$(grep -c "127.0.0.1 magento.local" "$hosts_file")"

    mbf::config::ensure_block "$hosts_file" "docker_stack" $'172.20.0.10 mysql.internal\n172.20.0.11 redis.internal' "top"
    local first_pass
    first_pass="$(cat "$hosts_file")"
    mbf::config::ensure_block "$hosts_file" "docker_stack" $'172.20.0.10 mysql.internal\n172.20.0.11 redis.internal' "top"
    assert_eq "$first_pass" "$(cat "$hosts_file")" "Re-running ensure_block with identical content must be byte-identical"

    mbf::config::ensure_block "$hosts_file" "docker_stack" $'172.20.0.10 mysql.internal\n172.20.0.20 opensearch.internal'
    assert_eq "1" "$(grep -c "# BEGIN MBF:docker_stack" "$hosts_file")"
    assert_eq "1" "$(mbf::config::line_number "$hosts_file" "# BEGIN MBF:docker_stack")"
    assert_contains "$(cat "$hosts_file")" "172.20.0.20 opensearch.internal"
    assert_not_contains "$(cat "$hosts_file")" "172.20.0.11 redis.internal"
}

function test_backup_rollback_delete_and_append_after_line() {
    local conf
    mbf::exec::tmpfile conf
    printf 'MAGENTO_MODE=production\nVARNISH_PORT=6081\nDEBUG_TOOLBAR=1\n' > "$conf"

    mbf::config::backup "$conf"
    mbf::config::replace_line "$conf" "MAGENTO_MODE" "MAGENTO_MODE=developer"
    assert_contains "$(cat "$conf")" "MAGENTO_MODE=developer"

    mbf::config::rollback "$conf" 2>/dev/null
    assert_contains "$(cat "$conf")" "MAGENTO_MODE=production"

    mbf::config::delete_line "$conf" "DEBUG_TOOLBAR"
    assert_not_contains "$(cat "$conf")" "DEBUG_TOOLBAR"

    local ln
    ln="$(mbf::config::line_number "$conf" "VARNISH_PORT=6081")"
    assert_eq "2" "$ln"
    mbf::config::append_after_line "$conf" "$ln" "REDIS_HOST=127.0.0.1"
    assert_eq "3" "$(mbf::config::line_number "$conf" "REDIS_HOST=127.0.0.1")"
}

function test_safe_load_env_and_read_secret_redaction() {
    local work_dir env_file secret_file pwn_file
    mbf::exec::tmpdir work_dir
    env_file="${work_dir}/.env"
    secret_file="${work_dir}/db_pass.secret"
    pwn_file="${work_dir}/pwned"

    cat <<EOF > "$env_file"
# Sample production dotenv
APP_ENV=production
export APP_NAME="Magento 2 Store"
SINGLE_QUOTED='hello world'
INJECTION_TEST="\$(touch ${pwn_file})"
EXISTING_VAR=from_file
EOF

    export EXISTING_VAR="from_env"
    mbf::config::load_env "$env_file" 0
    assert_eq "production" "$APP_ENV"
    assert_eq "Magento 2 Store" "$APP_NAME"
    assert_eq "hello world" "$SINGLE_QUOTED"
    assert_eq "from_env" "$EXISTING_VAR" "Existing env var must win when override=0"
    assert_eq "no" "$([ -e "$pwn_file" ] && echo yes || echo no)" "load_env must NEVER execute shell command substitutions"

    mbf::config::load_env "$env_file" 1
    assert_eq "from_file" "$EXISTING_VAR" "override=1 should replace existing env var"

    printf 'TopSecretPass_99\n' > "$secret_file"
    export MY_DB_PASS_FILE="$secret_file"
    mbf::config::read_secret MY_DB_PASS
    assert_eq "TopSecretPass_99" "$MY_DB_PASS"

    local log_out
    log_out="$(NO_COLOR=1 mbf::log::info "Connecting with ${MY_DB_PASS}" 2>&1)"
    assert_contains "$log_out" "Connecting with ***"
    assert_not_contains "$log_out" "TopSecretPass_99"
    unset MY_DB_PASS MY_DB_PASS_FILE EXISTING_VAR APP_ENV APP_NAME SINGLE_QUOTED INJECTION_TEST
}

run_test_suite "Config File Manipulation & Backup (mbf::config::*)"
