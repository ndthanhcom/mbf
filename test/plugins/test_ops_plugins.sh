#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use cron security database backup notify exec

function test_cron_plugin_prefix_collision_and_strict_guarded_run() {
    local work_dir
    mbf::exec::tmpdir work_dir
    export MBF_CRONTAB_FILE="${work_dir}/crontab"
    export MBF_LOCK_DIR="$work_dir"

    printf '0 0 * * * /usr/bin/existing_unmanaged_job\n' > "$MBF_CRONTAB_FILE"

    # Regression B1: removing `backup` must NOT remove `backup_db`
    mbf::cron::set "backup_db" "0 1 * * *" "/usr/local/bin/backup-db.sh"
    mbf::cron::set "backup"    "0 2 * * *" "/usr/local/bin/backup-files.sh"
    mbf::cron::remove "backup"
    assert_eq "1" "$(mbf::cron::list | grep -c "mbf:id=backup_db")"
    assert_eq "0" "$(mbf::cron::list | grep -c "mbf:id=backup$" || true)"

    mbf::cron::disable "backup_db"
    assert_contains "$(cat "$MBF_CRONTAB_FILE")" "#MBF_DISABLED# 0 1 * * *"

    mbf::cron::enable "backup_db"
    assert_not_contains "$(cat "$MBF_CRONTAB_FILE")" "#MBF_DISABLED#"

    # Regression B9: removing the last managed cron job when file has no other lines must succeed under strict mode
    : > "$MBF_CRONTAB_FILE"
    mbf::cron::set "only_job" "*/5 * * * *" "/usr/bin/true"
    mbf::cron::remove "only_job"
    assert_eq "0" "$(mbf::cron::list | grep -c "mbf:id=only_job" || true)"

    # Regression B8: under mbf::strict, a failing run_guarded command must still release lock & trigger alert
    local alert_file="${work_dir}/alert_fired.txt"
    function mbf::notify::alert() {
        printf '%s|%s\n' "$1" "$2" > "$alert_file"
    }
    local guard_rc=0
    mbf::cron::run_guarded "failing_indexer" false >/dev/null 2>&1 || guard_rc=$?
    assert_eq "1" "$guard_rc"
    assert_eq "no" "$([ -d "${work_dir}/mbf.cron_failing_indexer.lock" ] && echo yes || echo no)"
    assert_file_exists "$alert_file"
    assert_contains "$(cat "$alert_file")" "Cron Failed: failing_indexer"
}

function test_security_ssh_dropin_hardening_and_firewall() {
    local work_dir sshd_conf passwd_file
    mbf::exec::tmpdir work_dir
    sshd_conf="${work_dir}/sshd_config"
    passwd_file="${work_dir}/passwd"
    mkdir -p "${sshd_conf}.d"

    # Regression B13: drop-in `sshd_config.d/50-cloud-init.conf` overrides main `sshd_config`
    printf 'PasswordAuthentication yes\n' > "${sshd_conf}.d/50-cloud-init.conf"
    cat <<'EOF' > "$sshd_conf"
Port 22
PermitRootLogin yes
PasswordAuthentication no
EOF

    local audit_out
    audit_out="$(mbf::security::audit_ssh "$sshd_conf")"
    assert_contains "$audit_out" "[RISK] PermitRootLogin is enabled"
    assert_contains "$audit_out" "[WARN] PasswordAuthentication is enabled"

    mbf::security::harden_ssh "$sshd_conf" 1 >/dev/null
    assert_file_exists "${sshd_conf}.mbf.bak"
    assert_contains "$(cat "$sshd_conf")" "PermitRootLogin no"
    assert_contains "$(cat "${sshd_conf}.d/50-cloud-init.conf")" "PasswordAuthentication no"

    printf 'root:x:0:0:root:/root:/bin/bash\n' > "$passwd_file"
    assert_contains "$(mbf::security::audit_system "$passwd_file")" "UID 0 Accounts"

    mock_cmd "ufw" 0
    mock_cmd "apt-get" 0
    mock_cmd "systemctl" 0
    export MBF_FIREWALL_BACKEND="ufw"
    export MBF_PKG_MANAGER_OVERRIDE="apt-get"
    export MBF_ENV_TYPE_OVERRIDE="gitbash"
    assert_eq "ufw" "$(mbf::security::fw_backend)"
    mbf::security::fw_allow 8080 "tcp" >/dev/null
    mbf::security::fw_enable_baseline 2222 >/dev/null
    mbf::security::fw_deny 3306 "tcp" >/dev/null
    mbf::security::install_fail2ban >/dev/null
    assert_called_with "ufw" "allow 2222/tcp"
    assert_called_with "ufw" "deny 3306/tcp"
    unset MBF_FIREWALL_BACKEND MBF_PKG_MANAGER_OVERRIDE MBF_ENV_TYPE_OVERRIDE
}

function test_database_postgres_mysql_and_atomic_dump() {
    local work_dir dump_file
    mbf::exec::tmpdir work_dir
    dump_file="${work_dir}/magento2.sql.gz"

    mock_cmd "mysql" 0
    mock_cmd "psql" 0
    mock_cmd "redis-server" 0
    mock_cmd "sudo" 0
    mock_cmd "systemctl" 0
    export MBF_ENV_TYPE_OVERRIDE="gitbash"

    mbf::database::ensure_mysql >/dev/null
    mbf::database::ensure_postgres >/dev/null
    mbf::database::ensure_redis >/dev/null

    # Regression B6: Postgres create_db_and_user must run CREATE DATABASE even when log::info writes to stdout
    mbf::database::create_db_and_user "mysql" "magento2_prod" "m2_user" "s3cr'3t" >/dev/null
    assert_called_with "mysql" "CREATE DATABASE IF NOT EXISTS \`magento2_prod\`"
    mbf::database::create_db_and_user "postgres" "analytics_db" "pg_user" "p@ss" >/dev/null
    assert_called_with "sudo" "-H -u postgres -- psql -v ON_ERROR_STOP=1"

    # Regression B15: Failed mysqldump must return 1 and NOT leave an empty .sql.gz file
    mock_cmd "mysqldump" 1
    local dump_rc=0
    mbf::database::dump "mysql" "magento2_prod" "$dump_file" 2>/dev/null || dump_rc=$?
    assert_eq "1" "$dump_rc"
    assert_eq "no" "$([ -f "$dump_file" ] && echo yes || echo no)"

    # Successful mysqldump + restore
    mock_cmd "mysqldump" 0 "CREATE TABLE sales_order (id INT);"
    mbf::database::dump "mysql" "magento2_prod" "$dump_file"
    assert_file_exists "$dump_file"
    mbf::database::restore "mysql" "magento2_prod" "$dump_file"
    unset MBF_ENV_TYPE_OVERRIDE
}

function test_backup_plugin_archive_verify_and_prune() {
    local work_dir src_dir dest_dir archive
    mbf::exec::tmpdir work_dir
    src_dir="${work_dir}/magento_media"
    dest_dir="${work_dir}/backups"
    mkdir -p "$src_dir"
    printf 'catalog_product_image\n' > "${src_dir}/hero.jpg"

    archive="$(mbf::backup::archive_dir "$src_dir" "$dest_dir" "m2_media")"
    assert_file_exists "$archive"
    assert_file_exists "${archive}.sha256"
    mbf::backup::verify "$archive"
    mbf::backup::prune "$dest_dir" 7
    assert_file_exists "$archive" "Recent backup should not be pruned"
}

run_test_suite "Plugins: Cron, Security, Database & Backup"
