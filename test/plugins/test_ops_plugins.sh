#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use cron security backup notify exec

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
# Note: PermitRootLogin and PasswordAuthentication defaults are documented here
Port 22
PermitRootLogin yes
PasswordAuthentication no
#PermitEmptyPasswords yes
EOF

    local audit_out
    audit_out="$(mbf::security::audit_ssh "$sshd_conf")"
    assert_contains "$audit_out" "[RISK] PermitRootLogin is enabled"
    assert_contains "$audit_out" "[WARN] PasswordAuthentication is enabled"

    mbf::security::harden_ssh "$sshd_conf" 1 >/dev/null
    assert_file_exists "${sshd_conf}.mbf.bak"
    assert_contains "$(cat "$sshd_conf")" "# Note: PermitRootLogin and PasswordAuthentication defaults are documented here"
    assert_contains "$(cat "$sshd_conf")" "PermitRootLogin no"
    assert_contains "$(cat "$sshd_conf")" "PermitEmptyPasswords no"
    assert_eq "1" "$(grep -c '^PermitRootLogin no$' "$sshd_conf")" "Must not turn prose comments into duplicate directives"
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
