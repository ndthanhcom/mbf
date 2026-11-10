#!/usr/bin/env bash
# mbf:requires log json
# ==============================================================================
# mbf plugin: notify
# Server Email, Slack Webhook, and Telegram Bot Alerting
# ==============================================================================

# Send email on server using mail/mailx, sendmail, msmtp, or custom MBF_MAIL_CMD
# Usage: mbf::notify::email <to_address> <subject> <body>
function mbf::notify::email() {
    local to="${1:-${MBF_MAIL_TO:-}}"
    local subject="${2:-[mbf] Server Notification}"
    local body="${3:-}"
    local from="${MBF_MAIL_FROM:-mbf@$(hostname 2>/dev/null || echo localhost)}"

    if [ -z "$to" ]; then
        mbf::log::error "mbf::notify::email: recipient address is required (arg 1 or MBF_MAIL_TO)"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would send email to '$to' with subject '$subject'"
        return 0
    fi

    if [ -n "${MBF_MAIL_CMD:-}" ]; then
        printf '%s\n' "$body" | "$MBF_MAIL_CMD" "$to" "$subject"
    elif command -v mail >/dev/null 2>&1; then
        printf '%s\n' "$body" | mail -s "$subject" "$to"
    elif command -v mailx >/dev/null 2>&1; then
        printf '%s\n' "$body" | mailx -s "$subject" "$to"
    elif command -v sendmail >/dev/null 2>&1; then
        {
            printf 'From: %s\nTo: %s\nSubject: %s\nContent-Type: text/plain; charset=UTF-8\n\n%s\n' "$from" "$to" "$subject" "$body"
        } | sendmail -t
    elif command -v msmtp >/dev/null 2>&1; then
        {
            printf 'From: %s\nTo: %s\nSubject: %s\n\n%s\n' "$from" "$to" "$subject" "$body"
        } | msmtp "$to"
    else
        mbf::log::error "mbf::notify::email: no mail client (mail, mailx, sendmail, msmtp) found"
        return 1
    fi
}

# Send alert message to Slack via Incoming Webhook URL
# Usage: mbf::notify::slack <message> [webhook_url]
function mbf::notify::slack() {
    local message="$1"
    local webhook="${2:-${MBF_SLACK_WEBHOOK:-}}"

    if [ -z "$message" ] || [ -z "$webhook" ]; then
        mbf::log::error "mbf::notify::slack: message and webhook URL (or MBF_SLACK_WEBHOOK) are required"
        return 1
    fi

    local payload
    payload="{\"text\":\"$(mbf::json::escape "$message")\"}"

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would POST Slack payload to $webhook: $payload"
        return 0
    fi

    curl -fsSL -X POST -H 'Content-Type: application/json' --data "$payload" "$webhook" >/dev/null
}

# Send alert message to Telegram via Bot API
# Usage: mbf::notify::telegram <message> [bot_token] [chat_id]
function mbf::notify::telegram() {
    local message="$1"
    local token="${2:-${MBF_TELEGRAM_BOT_TOKEN:-}}"
    local chat_id="${3:-${MBF_TELEGRAM_CHAT_ID:-}}"

    if [ -z "$message" ] || [ -z "$token" ] || [ -z "$chat_id" ]; then
        mbf::log::error "mbf::notify::telegram: message, token, and chat_id are required"
        return 1
    fi

    local api_url="${MBF_TELEGRAM_API_BASE:-https://api.telegram.org}/bot${token}/sendMessage"
    local payload
    payload="{\"chat_id\":\"$(mbf::json::escape "$chat_id")\",\"text\":\"$(mbf::json::escape "$message")\"}"

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would POST Telegram payload to $api_url: $payload"
        return 0
    fi

    curl -fsSL -X POST -H 'Content-Type: application/json' --data "$payload" "$api_url" >/dev/null
}

# Dispatch alert to all configured channels (MBF_SLACK_WEBHOOK, MBF_TELEGRAM_*, MBF_MAIL_TO)
# Usage: mbf::notify::alert <title> <message>
function mbf::notify::alert() {
    local title="$1"
    local message="${2:-$1}"
    local full_text="[${title}] ${message}"
    local sent_any=0 rc=0

    if [ -n "${MBF_SLACK_WEBHOOK:-}" ]; then
        sent_any=1
        mbf::notify::slack "$full_text" || rc=1
    fi
    if [ -n "${MBF_TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${MBF_TELEGRAM_CHAT_ID:-}" ]; then
        sent_any=1
        mbf::notify::telegram "$full_text" || rc=1
    fi
    if [ -n "${MBF_MAIL_TO:-}" ]; then
        sent_any=1
        mbf::notify::email "$MBF_MAIL_TO" "$title" "$message" || rc=1
    fi

    if [ "$sent_any" -eq 0 ]; then
        mbf::log::warn "mbf::notify::alert: no notification channel configured"
        return 1
    fi
    return $rc
}
