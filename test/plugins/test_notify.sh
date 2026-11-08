#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use notify fs

function test_json_escape() {
    local escaped
    escaped="$(_mbf_json_escape $'Line 1 "quoted"\nLine 2 \\backslash')"
    assert_eq 'Line 1 \"quoted\"\nLine 2 \\backslash' "$escaped"
}

function test_notify_email_with_custom_mailer() {
    local mail_capture
    mbf::fs::tmpfile mail_capture

    function _mock_mailer() {
        printf 'TO=%s|SUBJ=%s|BODY=%s\n' "$1" "$2" "$(cat)" > "$mail_capture"
    }

    MBF_MAIL_CMD="_mock_mailer"
    mbf::notify::email "ops@example.com" "Disk Alert" "Disk /var is at 92%"
    assert_eq "0" "$?"
    assert_contains "$(cat "$mail_capture")" "TO=ops@example.com|SUBJ=Disk Alert|BODY=Disk /var is at 92%"
}

function test_notify_slack_telegram_and_alert_dryrun() {
    MBF_DRYRUN="1"
    export MBF_SLACK_WEBHOOK="https://hooks.slack.com/services/T00/B00/X00"
    export MBF_TELEGRAM_BOT_TOKEN="123456:ABC"
    export MBF_TELEGRAM_CHAT_ID="-100987654"
    export MBF_MAIL_TO="admin@example.com"

    local alert_out
    alert_out="$(mbf::notify::alert "HIGH LOAD" "Load average is 12.4")"
    assert_eq "0" "$?"
    assert_contains "$alert_out" "Would POST Slack payload"
    assert_contains "$alert_out" "Would POST Telegram payload"
    assert_contains "$alert_out" "Would send email to 'admin@example.com'"
}

run_test_suite "Plugin: Notify (mbf::notify::*)"
