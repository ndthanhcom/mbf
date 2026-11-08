#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf_use notify

function test_json_escape() {
    local escaped
    escaped="$(_mbf_json_escape $'Line 1 "quoted"\nLine 2 \\backslash')"
    assert_eq 'Line 1 \"quoted\"\nLine 2 \\backslash' "$escaped"
}

function test_notify_email_with_custom_mailer_and_dryrun() {
    local mail_capture
    mail_capture="$(mbf_mktemp_file)"

    # Custom mailer function for testing
    function _mock_mailer() {
        local to="$1"
        local subj="$2"
        local body
        body="$(cat)"
        printf 'TO=%s|SUBJ=%s|BODY=%s\n' "$to" "$subj" "$body" > "$mail_capture"
    }

    MBF_MAIL_CMD="_mock_mailer"
    notify_email "ops@example.com" "Disk Alert" "Disk /var is at 92%"
    assert_eq "0" "$?"

    local captured
    captured="$(cat "$mail_capture")"
    assert_contains "$captured" "TO=ops@example.com|SUBJ=Disk Alert|BODY=Disk /var is at 92%"
    unset MBF_MAIL_CMD
}

function test_notify_slack_and_telegram_dryrun() {
    MBF_DRYRUN="1"

    local slack_out
    slack_out="$(notify_slack "Server CPU > 90%" "https://hooks.slack.com/services/T00/B00/X00")"
    assert_eq "0" "$?"
    assert_contains "$slack_out" "Would POST Slack payload"
    assert_contains "$slack_out" 'Server CPU > 90%'

    local tg_out
    tg_out="$(notify_telegram "DB replica lag warning" "123456:ABC-DEF" "-100987654")"
    assert_eq "0" "$?"
    assert_contains "$tg_out" "Would POST Telegram payload"
    assert_contains "$tg_out" '"chat_id":"-100987654"'

    MBF_DRYRUN="0"
}

function test_notify_alert_unified_dispatcher() {
    MBF_DRYRUN="1"
    export MBF_SLACK_WEBHOOK="https://hooks.slack.com/services/T00/B00/X00"
    export MBF_TELEGRAM_BOT_TOKEN="123456:ABC"
    export MBF_TELEGRAM_CHAT_ID="999999"
    export MBF_MAIL_TO="admin@example.com"

    local alert_out
    alert_out="$(notify_alert "HIGH LOAD" "Load average is 12.4")"
    assert_eq "0" "$?"
    assert_contains "$alert_out" "Would POST Slack payload"
    assert_contains "$alert_out" "Would POST Telegram payload"
    assert_contains "$alert_out" "Would send email to 'admin@example.com'"

    unset MBF_SLACK_WEBHOOK MBF_TELEGRAM_BOT_TOKEN MBF_TELEGRAM_CHAT_ID MBF_MAIL_TO
    MBF_DRYRUN="0"
}

run_test_suite "Notifications (Email, Slack, Telegram)"
