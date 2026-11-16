#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use notify exec

function test_notify_email_slack_telegram_and_alert_channels() {
    local work_dir mail_capture
    mbf::exec::tmpdir work_dir
    mail_capture="${work_dir}/mail.txt"

    function _mock_mailer() {
        printf 'TO=%s|SUBJ=%s|BODY=%s\n' "$1" "$2" "$(cat)" > "$mail_capture"
    }
    MBF_MAIL_CMD="_mock_mailer" mbf::notify::email "ops@example.com" "Varnish Down" "Port 6081 unreachable"
    assert_contains "$(cat "$mail_capture")" "TO=ops@example.com|SUBJ=Varnish Down|BODY=Port 6081 unreachable"

    # R5: Verify slack and telegram route through mbf::net::post_json -> curl
    mock_cmd "curl" 0 "ok"
    mbf::notify::slack "Deployment finished" "https://hooks.slack.com/services/T00/B00/X00" >/dev/null
    assert_called_with "curl" "https://hooks.slack.com/services/T00/B00/X00"

    mbf::notify::telegram "Redis failover" "123456:ABC" "-100987654" >/dev/null
    assert_called_with "curl" "https://api.telegram.org/bot123456:ABC/sendMessage"

    MBF_DRYRUN="1"
    export MBF_SLACK_WEBHOOK="https://hooks.slack.com/services/T00/B00/X00"
    export MBF_TELEGRAM_BOT_TOKEN="123456:ABC"
    export MBF_TELEGRAM_CHAT_ID="-100987654"
    export MBF_MAIL_TO="admin@example.com"

    local alert_out
    alert_out="$(mbf::notify::alert "HIGH LOAD" "Load average is 14.2 on web01")"
    assert_contains "$alert_out" "https://hooks.slack.com/services/T00/B00/X00"
    assert_contains "$alert_out" "https://api.telegram.org/bot123456:ABC/sendMessage"
    assert_contains "$alert_out" "Would send email to 'admin@example.com'"
    MBF_DRYRUN="0"
}

function test_notify_signed_saas_webhook() {
    MBF_DRYRUN="1"
    export MBF_SAAS_WEBHOOK_URL="https://saas.example.com/api/webhook"
    export MBF_SAAS_SECRET="webhook_hmac_secret"

    local evt_out
    evt_out="$(mbf::notify::webhook "job_101" "deploy_magento" "completed" "Release 20261116 live")"
    assert_contains "$evt_out" "Would HTTP POST https://saas.example.com/api/webhook"
    assert_contains "$evt_out" '"job_id":"job_101"'
    assert_contains "$evt_out" '"step":"deploy_magento"'
    assert_contains "$evt_out" '"message":"Release 20261116 live"'
    MBF_DRYRUN="0"
}

run_test_suite "Plugin: Notify & Signed Webhooks (mbf::notify::*)"
