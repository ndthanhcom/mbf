#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use monitor fs

function test_monitor_resources_and_performance() {
    local res_out perf_out
    res_out="$(mbf::monitor::resources)"
    assert_contains "$res_out" "SERVER RESOURCES"
    assert_contains "$res_out" "Hostname :"
    assert_contains "$res_out" "CPU      :"

    perf_out="$(mbf::monitor::performance)"
    assert_contains "$perf_out" "PERFORMANCE CHECK"
    assert_contains "$perf_out" "[Top 5 CPU Processes]"
}

function test_monitor_logs_analyzer() {
    local mock_dir sample_log
    mbf::fs::tmpdir mock_dir
    sample_log="${mock_dir}/syslog"
    cat <<'EOF' > "$sample_log"
Nov 05 10:00:01 srv systemd[1]: Started Daily apt download activities.
Nov 05 10:01:12 srv sshd[1234]: Failed password for invalid user admin from 192.0.2.99 port 51234 ssh2
Nov 05 10:02:45 srv kernel: [12345.67] Out of memory: Killed process 999 (php-fpm)
Nov 05 10:03:00 srv nginx[4321]: [error] 4321#0: *1 connect() failed (111: Connection refused)
EOF

    local log_out
    log_out="$(mbf::monitor::logs "$sample_log" 5)"
    assert_contains "$log_out" "Total error/critical matches: 2"
    assert_contains "$log_out" "Total auth failure matches  : 1"
    assert_contains "$log_out" "Out of memory: Killed process 999"
    assert_contains "$log_out" "Failed password for invalid user admin"
}

function test_monitor_firewall_and_cron() {
    local mock_dir cron_dir fw_out cron_out
    mbf::fs::tmpdir mock_dir
    cron_dir="${mock_dir}/cron.d"
    mkdir -p "$cron_dir"
    printf '# comment line\n0 2 * * * root /usr/local/bin/backup.sh\n' > "${cron_dir}/backup"

    fw_out="$(mbf::monitor::firewall)"
    assert_contains "$fw_out" "FIREWALL & PORTS CHECK"
    assert_contains "$fw_out" "[Listening Network Ports]"

    cron_out="$(mbf::monitor::cron "$cron_dir")"
    assert_contains "$cron_out" "CRON JOBS CHECK"
    assert_contains "$cron_out" "/usr/local/bin/backup.sh"
}

function test_monitor_history_and_full_report() {
    local mock_dir hist_file hist_out full_out
    mbf::fs::tmpdir mock_dir
    hist_file="${mock_dir}/.bash_history"
    cat <<'EOF' > "$hist_file"
ls -la
cd /var/www
sudo systemctl restart nginx
rm -rf /tmp/cache_old
git status
EOF

    hist_out="$(mbf::monitor::history "$hist_file" 10)"
    assert_contains "$hist_out" "COMMAND HISTORY REVIEW"
    assert_contains "$hist_out" "sudo systemctl restart nginx"
    assert_contains "$hist_out" "rm -rf /tmp/cache_old"

    full_out="$(mbf::monitor::report "${mock_dir}/syslog" "$hist_file")"
    assert_contains "$full_out" "MBF LINUX SERVER MONITORING & REVIEW REPORT"
}

run_test_suite "Plugin: Monitor (mbf::monitor::*)"
