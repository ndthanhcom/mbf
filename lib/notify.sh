#!/usr/bin/env bash
# ==============================================================================
# mbf module: notify
# Server Email, Slack Webhook, and Telegram Bot Alerting
#
# Environment Variables:
#   MBF_MAIL_TO            : Default recipient email address
#   MBF_MAIL_FROM          : Optional sender email address
#   MBF_SLACK_WEBHOOK      : Slack Incoming Webhook URL
#   MBF_TELEGRAM_BOT_TOKEN : Telegram Bot API token
#   MBF_TELEGRAM_CHAT_ID   : Telegram target chat/channel ID
# ==============================================================================

# Escape string for safe embedding inside a JSON double-quoted value
function _mbf_json_escape() {
    local text="$1"
    text="${text//\\/\\\\}"
    text="${text//\"/\\\"}"
    text="${text//$'\r'/}"
    text="${text//$'\n'/\\n}"
    text="${text//$'\t'/\\t}"
    printf '%s' "$text"
}

# Send email on server using mail/mailx, sendmail, or msmtp
# Usage: notify_email <to_address> <subject> <body>
function notify_email() {
    local to="${1:-${MBF_MAIL_TO:-}}"
    local subject="${2:-"[mbf] Server Notification"}"
    local body="${3:-}"
    local from="${MBF_MAIL_FROM:-mbf@$(hostname 2>/dev/null || echo localhost)}"
    local dryrun="${MBF_DRYRUN:-${I7R_DRYRUN:-0}}"

    if [ -z "$to" ]; then
        log_error "notify_email: recipient address is required (pass arg 1 or set MBF_MAIL_TO)"
        return 1
    fi

    if [ "$dryrun" == "1" ]; then
        log_info "[DRYRUN] Would send email to '$to' with subject '$subject'"
        return 0
    fi

    if [ -n "${MBF_MAIL_CMD:-}" ]; then
        printf '%s\n' "$body" | $MBF_MAIL_CMD "$to" "$subject"
        return $?
    elif command -v mail >/dev/null 2>&1; then
        printf '%s\n' "$body" | mail -s "$subject" "$to"
        return $?
    elif command -v mailx >/dev/null 2>&1; then
        printf '%s\n' "$body" | mailx -s "$subject" "$to"
        return $?
    elif command -v sendmail >/dev/null 2>&1; then
        {
            printf 'From: %s\n' "$from"
            printf 'To: %s\n' "$to"
            printf 'Subject: %s\n' "$subject"
            printf 'Content-Type: text/plain; charset=UTF-8\n\n'
            printf '%s\n' "$body"
        } | sendmail -t
        return $?
    elif command -v msmtp >/dev/null 2>&1; then
        {
            printf 'From: %s\n' "$from"
            printf 'To: %s\n' "$to"
            printf 'Subject: %s\n\n' "$subject"
            printf '%s\n' "$body"
        } | msmtp "$to"
        return $?
    else
        log_error "notify_email: no mail client (mail, mailx, sendmail, msmtp) found on server"
        return 1
    fi
}

# Send alert message to Slack via Incoming Webhook URL
# Usage: notify_slack <message> [webhook_url]
function notify_slack() {
    local message="$1"
    local webhook="${2:-${MBF_SLACK_WEBHOOK:-}}"
    local dryrun="${MBF_DRYRUN:-${I7R_DRYRUN:-0}}"

    if [ -z "$message" ]; then
        log_error "notify_slack: message is required"
        return 1
    fi
    if [ -z "$webhook" ]; then
        log_error "notify_slack: webhook URL is required (pass arg 2 or set MBF_SLACK_WEBHOOK)"
        return 1
    fi

    local escaped_msg
    escaped_msg="$(_mbf_json_escape "$message")"
    local payload="{\"text\":\"${escaped_msg}\"}"

    if [ "$dryrun" == "1" ]; then
        log_info "[DRYRUN] Would POST Slack payload to $webhook: $payload"
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        log_error "notify_slack: curl is required to send Slack notifications"
        return 1
    fi

    curl -fsSL -X POST -H 'Content-type: application/json' --data "$payload" "$webhook" >/dev/null
}

# Send alert message to Telegram via Bot API
# Usage: notify_telegram <message> [bot_token] [chat_id]
function notify_telegram() {
    local message="$1"
    local token="${2:-${MBF_TELEGRAM_BOT_TOKEN:-}}"
    local chat_id="${3:-${MBF_TELEGRAM_CHAT_ID:-}}"
    local dryrun="${MBF_DRYRUN:-${I7R_DRYRUN:-0}}"

    if [ -z "$message" ]; then
        log_error "notify_telegram: message is required"
        return 1
    fi
    if [ -z "$token" ] || [ -z "$chat_id" ]; then
        log_error "notify_telegram: bot token and chat_id are required (set MBF_TELEGRAM_BOT_TOKEN and MBF_TELEGRAM_CHAT_ID)"
        return 1
    fi

    local escaped_msg
    escaped_msg="$(_mbf_json_escape "$message")"
    local escaped_chat
    escaped_chat="$(_mbf_json_escape "$chat_id")"
    local api_url="${MBF_TELEGRAM_API_BASE:-https://api.telegram.org}/bot${token}/sendMessage"
    local payload="{\"chat_id\":\"${escaped_chat}\",\"text\":\"${escaped_msg}\"}"

    if [ "$dryrun" == "1" ]; then
        log_info "[DRYRUN] Would POST Telegram payload to $api_url: $payload"
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        log_error "notify_telegram: curl is required to send Telegram notifications"
        return 1
    fi

    curl -fsSL -X POST -H 'Content-Type: application/json' --data "$payload" "$api_url" >/dev/null
}

# Send alert across all configured notification channels (Slack, Telegram, Email)
# Usage: notify_alert <title> <message>
function notify_alert() {
    local title="$1"
    local message="${2:-$1}"
    local full_text="[${title}] ${message}"
    local sent_any=0
    local rc=0

    if [ -n "${MBF_SLACK_WEBHOOK:-}" ]; then
        sent_any=1
        notify_slack "$full_text" || rc=1
    fi

    if [ -n "${MBF_TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${MBF_TELEGRAM_CHAT_ID:-}" ]; then
        sent_any=1
        notify_telegram "$full_text" || rc=1
    fi

    if [ -n "${MBF_MAIL_TO:-}" ]; then
        sent_any=1
        notify_email "$MBF_MAIL_TO" "$title" "$message" || rc=1
    fi

    if [ "$sent_any" -eq 0 ]; then
        log_warn "notify_alert: no notification channel configured (set MBF_SLACK_WEBHOOK, MBF_TELEGRAM_*, or MBF_MAIL_TO)"
        return 1
    fi

    return $rc
}
