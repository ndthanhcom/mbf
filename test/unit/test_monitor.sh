#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf_use monitor

MOCK_DIR=""

function setup() {
    MOCK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mbf.monitor.XXXXXX")"
}

function teardown() {
    rm -rf "$MOCK_DIR"
}

function test_monitor_resources_and_performance() {
    local res_out
    res_out="$(monitor_resources)"
    assert_contains "$res_out" "SERVER RESOURCES"
    assert_contains "$res_out" "Hostname :"
    assert_contains "$res_out" "CPU      :"

    local perf_out
    perf_out="$(monitor_performance)"
    assert_contains "$perf_out" "PERFORMANCE CHECK"
    assert_contains "$perf_out" "[Top 5 CPU Processes]"
}

function test_monitor_logs_analyzer() {
    local sample_log="${MOCK_DIR}/syslog"
    cat <<'EOF' > "$sample_log"
Nov 05 10:00:01 srv systemd[1]: Started Daily apt download activities.
Nov 05 10:01:12 srv sshd[1234]: Failed password for invalid user admin from 192.0.2.99 port 51234 ssh2
Nov 05 10:02:45 srv kernel: [12345.67] Out of memory: Killed process 999 (php-fpm)
Nov 05 10:03:00 srv nginx[4321]: [error] 4321#0: *1 connect() failed (111: Connection refused)
EOF

    local log_out
    log_out="$(monitor_logs "$sample_log" 5)"
    assert_contains "$log_out" "Total error/critical matches: 2"
    assert_contains "$log_out" "Total auth failure matches  : 1"
    assert_contains "$log_out" "Out of memory: Killed process 999"
    assert_contains "$log_out" "Failed password for invalid user admin"
}

function test_monitor_firewall_and_cron() {
    local fw_out
    fw_out="$(monitor_firewall)"
    assert_contains "$fw_out" "FIREWALL & PORTS CHECK"
    assert_contains "$fw_out" "[Listening Network Ports]"

    local cron_dir="${MOCK_DIR}/cron.d"
    mkdir -p "$cron_dir"
    printf '# comment line\n0 2 * * * root /usr/local/bin/backup.sh\n' > "${cron_dir}/backup"

    local cron_out
    cron_out="$(monitor_cron "$cron_dir")"
    assert_contains "$cron_out" "CRON JOBS CHECK"
    assert_contains "$cron_out" "/usr/local/bin/backup.sh"
}

function test_monitor_history_and_full_report() {
    local hist_file="${MOCK_DIR}/.bash_history"
    cat <<'EOF' > "$hist_file"
ls -la
cd /var/www
sudo systemctl restart nginx
rm -rf /tmp/cache_old
git status
EOF

    local hist_out
    hist_out="$(monitor_history "$hist_file" 10)"
    assert_contains "$hist_out" "COMMAND HISTORY REVIEW"
    assert_contains "$hist_out" "sudo systemctl restart nginx"
    assert_contains "$hist_out" "rm -rf /tmp/cache_old"

    local full_out
    full_out="$(monitor_server_report "${MOCK_DIR}/syslog" "$hist_file")"
    assert_contains "$full_out" "MBF LINUX SERVER MONITORING & REVIEW REPORT"
}

run_test_suite "Linux Server Monitoring & Review"
