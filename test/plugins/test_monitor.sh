#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use monitor exec

function test_monitor_resources_performance_and_logs() {
    local mock_dir sample_log res_out perf_out log_out
    mbf::exec::tmpdir mock_dir

    res_out="$(mbf::monitor::resources)"
    assert_contains "$res_out" "SERVER RESOURCES"
    assert_contains "$res_out" "Hostname :"

    perf_out="$(mbf::monitor::performance)"
    assert_contains "$perf_out" "PERFORMANCE CHECK"
    assert_contains "$perf_out" "[Top 5 CPU Processes]"

    sample_log="${mock_dir}/syslog"
    cat <<'EOF' > "$sample_log"
Nov 14 10:00:01 prod-web01 systemd[1]: Started Magento Cron Runner.
Nov 14 10:01:12 prod-web01 sshd[1234]: Failed password for invalid user root from 198.51.100.42 port 51234 ssh2
Nov 14 10:02:45 prod-web01 kernel: [12345.67] Out of memory: Killed process 999 (php-fpm8.2)
Nov 14 10:03:00 prod-web01 nginx[4321]: [error] 4321#0: *1 upstream timed out (110: Connection timed out)
EOF

    log_out="$(mbf::monitor::logs "$sample_log" 5)"
    assert_contains "$log_out" "Total error/critical matches: 2"
    assert_contains "$log_out" "Total auth failure matches  : 1"
    assert_contains "$log_out" "Out of memory: Killed process 999"
}

function test_monitor_firewall_cron_history_report_and_json() {
    local mock_dir cron_dir hist_file sshd_conf fw_out cron_out hist_out full_out review_json
    mbf::exec::tmpdir mock_dir
    cron_dir="${mock_dir}/cron.d"
    mkdir -p "$cron_dir"
    printf '*/5 * * * * www-data /usr/bin/php /var/www/magento2/bin/magento cron:run\n' > "${cron_dir}/magento"

    fw_out="$(mbf::monitor::firewall)"
    assert_contains "$fw_out" "FIREWALL & PORTS CHECK"

    cron_out="$(mbf::monitor::cron "$cron_dir")"
    assert_contains "$cron_out" "bin/magento cron:run"

    hist_file="${mock_dir}/.bash_history"
    printf 'cd /var/www/magento2\nsudo systemctl restart nginx\nrm -rf var/cache/*\n' > "$hist_file"
    hist_out="$(mbf::monitor::history "$hist_file" 10)"
    assert_contains "$hist_out" "sudo systemctl restart nginx"

    full_out="$(mbf::monitor::report "${mock_dir}/syslog" "$hist_file")"
    assert_contains "$full_out" "MBF LINUX SERVER MONITORING & REVIEW REPORT"

    sshd_conf="${mock_dir}/sshd_config"
    printf 'PermitRootLogin no\nPasswordAuthentication no\n' > "$sshd_conf"
    review_json="$(mbf::monitor::collect_review_json "$sshd_conf")"
    assert_eq "no" "$(mbf::json::get "$review_json" "ssh_permit_root_login")"
    assert_eq "no" "$(mbf::json::get "$review_json" "ssh_password_auth")"
}

run_test_suite "Plugin: Monitor & Server Review (mbf::monitor::*)"
