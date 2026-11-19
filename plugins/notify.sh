#!/usr/bin/env bash
# @mbf-module: notify
# mbf:requires log json net str
# ==============================================================================
# mbf plugin: notify
# Multi-Channel Messaging, Alerting (Email, Slack, Telegram) & Signed Webhooks
#
# Environment Variables:
#   MBF_MAIL_TO            : Default recipient email address
#   MBF_MAIL_FROM          : Sender email address (default: mbf@<hostname>)
#   MBF_MAIL_CMD           : Optional custom mail command hook receiving <to> <subject>
#   MBF_SLACK_WEBHOOK      : Slack Incoming Webhook URL
#   MBF_TELEGRAM_BOT_TOKEN : Telegram Bot API token
#   MBF_TELEGRAM_CHAT_ID   : Telegram destination chat/channel ID
#   MBF_SAAS_WEBHOOK_URL   : SaaS platform webhook endpoint for structured events
#   MBF_SAAS_SECRET        : Optional HMAC-SHA256 secret for signing webhook events
# ==============================================================================

# Send email notification using mail/mailx, sendmail, msmtp, or custom MBF_MAIL_CMD
# Usage: mbf::notify::email <to_address> <subject> <body>
function mbf::notify::email() {
    local to="${1:-${MBF_MAIL_TO:-}}"
    local subject="${2:-[mbf] Server Notification}"
    local body="${3:-}"
    local from="${MBF_MAIL_FROM:-}"
    [ -n "$from" ] || from="mbf@$(hostname 2>/dev/null || echo localhost)"

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
        printf 'From: %s\nTo: %s\nSubject: %s\nContent-Type: text/plain; charset=UTF-8\n\n%s\n' "$from" "$to" "$subject" "$body" | sendmail -t
    elif command -v msmtp >/dev/null 2>&1; then
        printf 'From: %s\nTo: %s\nSubject: %s\n\n%s\n' "$from" "$to" "$subject" "$body" | msmtp "$to"
    else
        mbf::log::error "mbf::notify::email: no mail client (mail, mailx, sendmail, msmtp) found"
        return 1
    fi
}

# Send alert message to Slack via Incoming Webhook URL (routed through mbf::net::post_json)
# Usage: mbf::notify::slack <message> [webhook_url]
function mbf::notify::slack() {
    local message="${1:-}"
    local webhook="${2:-${MBF_SLACK_WEBHOOK:-}}"

    if [ -z "$message" ] || [ -z "$webhook" ]; then
        mbf::log::error "mbf::notify::slack: message and webhook URL (or MBF_SLACK_WEBHOOK) are required"
        return 1
    fi

    local payload
    payload="$(mbf::json::object "text=${message}")"
    mbf::net::post_json "$webhook" "$payload"
}

# Send alert message to Telegram via Bot API (routed through mbf::net::post_json)
# Usage: mbf::notify::telegram <message> [bot_token] [chat_id]
function mbf::notify::telegram() {
    local message="${1:-}"
    local token="${2:-${MBF_TELEGRAM_BOT_TOKEN:-}}"
    local chat_id="${3:-${MBF_TELEGRAM_CHAT_ID:-}}"

    if [ -z "$message" ] || [ -z "$token" ] || [ -z "$chat_id" ]; then
        mbf::log::error "mbf::notify::telegram: message, token, and chat_id are required"
        return 1
    fi

    local api_url="${MBF_TELEGRAM_API_BASE:-https://api.telegram.org}/bot${token}/sendMessage"
    local payload
    payload="$(mbf::json::object "chat_id=${chat_id}" "text=${message}")"
    mbf::net::post_json "$api_url" "$payload"
}

# Send a structured JSON progress/status event to a SaaS or custom webhook
# Automatically computes an HMAC-SHA256 signature over `<job_id>:<step>:<status>:<timestamp>:<message>`
# when MBF_SAAS_SECRET is set.
# Usage: mbf::notify::webhook <job_id> <step> <status> <message> [webhook_url]
function mbf::notify::webhook() {
    local job_id="$1"
    local step="$2"
    local status="$3"
    local message="$4"
    local url="${5:-${MBF_SAAS_WEBHOOK_URL:-}}"

    if [ -z "$url" ]; then
        mbf::log::error "mbf::notify::webhook: webhook URL required (arg 5 or MBF_SAAS_WEBHOOK_URL)"
        return 1
    fi

    local host ts sig="" payload
    host="$(hostname 2>/dev/null || echo unknown)"
    ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

    if [ -n "${MBF_SAAS_SECRET:-}" ] && command -v openssl >/dev/null 2>&1; then
        sig="$(mbf::str::hmac_sha256 "$MBF_SAAS_SECRET" "${job_id}:${step}:${status}:${ts}:${message}")"
    fi

    payload="$(mbf::json::object \
        "job_id=${job_id}" \
        "host=${host}" \
        "step=${step}" \
        "status=${status}" \
        "message=${message}" \
        "timestamp=${ts}" \
        "signature=${sig}")"

    mbf::net::post_json "$url" "$payload"
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
    return "$rc"
}
