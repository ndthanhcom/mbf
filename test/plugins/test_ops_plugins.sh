#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use cron security firewall backup fs

function test_cron_plugin_crud_and_guarded_run() {
    local work_dir
    mbf::fs::tmpdir work_dir
    export MBF_CRONTAB_FILE="${work_dir}/crontab"
    export MBF_LOCK_DIR="$work_dir"

    printf '0 0 * * * /usr/bin/existing_unmanaged_job\n' > "$MBF_CRONTAB_FILE"

    mbf::cron::set "db_backup" "0 2 * * *" "/usr/local/bin/backup.sh"
    mbf::cron::set "db_backup" "30 3 * * *" "/usr/local/bin/backup_v2.sh"

    assert_eq "1" "$(mbf::cron::list | grep -c "mbf:id=db_backup")"
    assert_contains "$(mbf::cron::list)" "30 3 * * * /usr/local/bin/backup_v2.sh"
    assert_contains "$(cat "$MBF_CRONTAB_FILE")" "/usr/bin/existing_unmanaged_job"

    mbf::cron::disable "db_backup"
    assert_contains "$(cat "$MBF_CRONTAB_FILE")" "#MBF_DISABLED# 30 3 * * *"

    mbf::cron::enable "db_backup"
    assert_not_contains "$(cat "$MBF_CRONTAB_FILE")" "#MBF_DISABLED#"

    mbf::cron::remove "db_backup"
    assert_eq "0" "$(mbf::cron::list | grep -c "mbf:id=db_backup" || true)"

    local run_out
    run_out="$(mbf::cron::run_guarded "test_job" echo "CRON_GUARD_OK")"
    assert_contains "$run_out" "CRON_GUARD_OK"
}

function test_security_audit_and_ssh_hardening() {
    local work_dir sshd_conf
    mbf::fs::tmpdir work_dir
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
}

function test_firewall_and_backup_plugins() {
    local work_dir src_dir dest_dir archive
    mbf::fs::tmpdir work_dir
    src_dir="${work_dir}/site_data"
    dest_dir="${work_dir}/backups"
    mkdir -p "$src_dir"
    printf 'important_content\n' > "${src_dir}/index.html"

    archive="$(mbf::backup::archive_dir "$src_dir" "$dest_dir" "mysite")"
    assert_file_exists "$archive"
    assert_file_exists "${archive}.sha256"

    MBF_DRYRUN="1"
    export MBF_FIREWALL_BACKEND="ufw"
    local fw_out
    fw_out="$(mbf::firewall::enable_baseline 2222)"
    assert_contains "$fw_out" "2222/tcp"
    assert_contains "$fw_out" "Baseline firewall rules enabled"
}

run_test_suite "Plugins: Cron, Security, Firewall & Backup"
