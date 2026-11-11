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
Nov 12 10:00:01 prod-web01 systemd[1]: Started Magento Cron Runner.
Nov 12 10:01:12 prod-web01 sshd[1234]: Failed password for invalid user root from 198.51.100.42 port 51234 ssh2
Nov 12 10:02:45 prod-web01 kernel: [12345.67] Out of memory: Killed process 999 (php-fpm8.2)
Nov 12 10:03:00 prod-web01 nginx[4321]: [error] 4321#0: *1 upstream timed out (110: Connection timed out)
EOF

    log_out="$(mbf::monitor::logs "$sample_log" 5)"
    assert_contains "$log_out" "Total error/critical matches: 2"
    assert_contains "$log_out" "Total auth failure matches  : 1"
    assert_contains "$log_out" "Out of memory: Killed process 999"
}

function test_monitor_firewall_cron_history_and_report() {
    local mock_dir cron_dir hist_file fw_out cron_out hist_out full_out
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
}

function test_monitor_saas_telemetry_and_multichannel_alerts() {
    local work_dir sshd_conf mail_capture
    mbf::exec::tmpdir work_dir
    sshd_conf="${work_dir}/sshd_config"
    mail_capture="${work_dir}/mail.txt"
    printf 'PermitRootLogin no\nPasswordAuthentication no\n' > "$sshd_conf"

    local review_json
    review_json="$(mbf::monitor::collect_review_json "$sshd_conf")"
    assert_eq "no" "$(mbf::json::get "$review_json" "ssh_permit_root_login")"
    assert_eq "no" "$(mbf::json::get "$review_json" "ssh_password_auth")"

    function _mock_mailer() {
        printf 'TO=%s|SUBJ=%s|BODY=%s\n' "$1" "$2" "$(cat)" > "$mail_capture"
    }
    MBF_MAIL_CMD="_mock_mailer" mbf::monitor::notify_email "ops@example.com" "Varnish Down" "Port 6081 unreachable"
    assert_contains "$(cat "$mail_capture")" "TO=ops@example.com|SUBJ=Varnish Down|BODY=Port 6081 unreachable"

    MBF_DRYRUN="1"
    export MBF_SAAS_WEBHOOK_URL="https://saas.example.com/api/webhook"
    export MBF_SAAS_SECRET="webhook_hmac_secret"
    local evt_out
    evt_out="$(mbf::monitor::send_event "job_101" "audit_server" "completed" "Server audit clean")"
    assert_contains "$evt_out" "Would HTTP POST https://saas.example.com/api/webhook"
    assert_contains "$evt_out" '"job_id":"job_101"'

    export MBF_SLACK_WEBHOOK="https://hooks.slack.com/services/T00/B00/X00"
    export MBF_TELEGRAM_BOT_TOKEN="123456:ABC"
    export MBF_TELEGRAM_CHAT_ID="-100987654"
    export MBF_MAIL_TO="admin@example.com"
    local alert_out
    alert_out="$(mbf::monitor::alert "HIGH LOAD" "Load average is 14.2 on web01")"
    assert_contains "$alert_out" "Would POST Slack payload"
    assert_contains "$alert_out" "Would POST Telegram payload"
    assert_contains "$alert_out" "Would send email to 'admin@example.com'"
}

run_test_suite "Plugin: Monitor, SaaS Telemetry & Alerting (mbf::monitor::*)"
