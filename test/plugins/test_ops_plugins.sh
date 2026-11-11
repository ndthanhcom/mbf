#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use cron security database exec

function test_cron_plugin_crud_and_guarded_run() {
    local work_dir
    mbf::exec::tmpdir work_dir
    export MBF_CRONTAB_FILE="${work_dir}/crontab"
    export MBF_LOCK_DIR="$work_dir"

    printf '0 0 * * * /usr/bin/existing_unmanaged_job\n' > "$MBF_CRONTAB_FILE"

    mbf::cron::set "m2_indexer" "*/5 * * * *" "/usr/bin/php /var/www/m2/bin/magento indexer:reindex"
    mbf::cron::set "m2_indexer" "*/10 * * * *" "/usr/bin/php /var/www/m2/bin/magento indexer:reindex"

    assert_eq "1" "$(mbf::cron::list | grep -c "mbf:id=m2_indexer")"
    assert_contains "$(mbf::cron::list)" "*/10 * * * * /usr/bin/php /var/www/m2/bin/magento indexer:reindex"
    assert_contains "$(cat "$MBF_CRONTAB_FILE")" "/usr/bin/existing_unmanaged_job"

    mbf::cron::disable "m2_indexer"
    assert_contains "$(cat "$MBF_CRONTAB_FILE")" "#MBF_DISABLED# */10 * * * *"

    mbf::cron::enable "m2_indexer"
    assert_not_contains "$(cat "$MBF_CRONTAB_FILE")" "#MBF_DISABLED#"

    mbf::cron::remove "m2_indexer"
    assert_eq "0" "$(mbf::cron::list | grep -c "mbf:id=m2_indexer" || true)"

    local run_out
    run_out="$(mbf::cron::run_guarded "cache_warm" echo "CRON_GUARD_OK")"
    assert_contains "$run_out" "CRON_GUARD_OK"
}

function test_security_ssh_hardening_and_firewall_baseline() {
    local work_dir sshd_conf
    mbf::exec::tmpdir work_dir
    sshd_conf="${work_dir}/sshd_config"

    cat <<'EOF' > "$sshd_conf"
Port 22
PermitRootLogin yes
PasswordAuthentication yes
EOF

    local audit_out
    audit_out="$(mbf::security::audit_ssh "$sshd_conf")"
    assert_contains "$audit_out" "[RISK] PermitRootLogin is enabled"

    mbf::security::harden_ssh "$sshd_conf" 1 >/dev/null
    assert_file_exists "${sshd_conf}.mbf.bak"
    assert_contains "$(cat "$sshd_conf")" "PermitRootLogin no"
    assert_contains "$(cat "$sshd_conf")" "PasswordAuthentication no"

    MBF_DRYRUN="1"
    export MBF_FIREWALL_BACKEND="ufw"
    local fw_out
    fw_out="$(mbf::security::fw_enable_baseline 2222)"
    assert_contains "$fw_out" "2222/tcp"
    assert_contains "$fw_out" "Baseline firewall rules enabled"
}

function test_database_archive_and_backup_retention() {
    local work_dir src_dir dest_dir archive
    mbf::exec::tmpdir work_dir
    src_dir="${work_dir}/magento_media"
    dest_dir="${work_dir}/backups"
    mkdir -p "$src_dir"
    printf 'catalog_product_image\n' > "${src_dir}/hero.jpg"

    archive="$(mbf::database::archive_dir "$src_dir" "$dest_dir" "m2_media")"
    assert_file_exists "$archive"
    assert_file_exists "${archive}.sha256"

    MBF_DRYRUN="1"
    local db_out
    db_out="$(mbf::database::create_db_and_user "mysql" "magento2_prod" "m2_user" "s3cr3t")"
    assert_contains "$db_out" "Would create mysql database 'magento2_prod'"
}

run_test_suite "Plugins: Cron, Security (SSH + Firewall) & Database/Backup"
