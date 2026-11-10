#!/usr/bin/env bash
# mbf:requires log json http crypto monitor security
# ==============================================================================
# mbf plugin: agent
# SaaS Platform Telemetry, HMAC-Signed Event Callback & JSON Server Review Collector
# ==============================================================================

# Send a structured JSON progress/status event to the SaaS platform webhook
# Signs payload with HMAC-SHA256 if MBF_SAAS_SECRET is set
# Usage: mbf::agent::send_event <job_id> <step> <status> <message> [webhook_url]
function mbf::agent::send_event() {
    local job_id="$1"
    local step="$2"
    local status="$3"
    local message="$4"
    local url="${5:-${MBF_SAAS_WEBHOOK_URL:-}}"

    if [ -z "$url" ]; then
        mbf::log::error "mbf::agent::send_event: webhook URL required (arg 5 or MBF_SAAS_WEBHOOK_URL)"
        return 1
    fi

    local host ts sig="" payload
    host="$(hostname 2>/dev/null || echo unknown)"
    ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

    if [ -n "${MBF_SAAS_SECRET:-}" ] && command -v openssl >/dev/null 2>&1; then
        sig="$(mbf::crypto::hmac_sha256 "$MBF_SAAS_SECRET" "${job_id}:${step}:${status}:${ts}")"
    fi

    payload="$(mbf::json::object \
        "job_id=${job_id}" \
        "host=${host}" \
        "step=${step}" \
        "status=${status}" \
        "message=${message}" \
        "timestamp=${ts}" \
        "signature=${sig}")"

    mbf::http::post_json "$url" "$payload"
}

# Collect server resource, load, security, and cron metrics as a single JSON object for SaaS ingestion
# Usage: mbf::agent::collect_review_json [sshd_config_file]
function mbf::agent::collect_review_json() {
    local sshd_conf="${1:-/etc/ssh/sshd_config}"
    local host os_kernel cpu_cores load_1m root_login pass_auth

    host="$(hostname 2>/dev/null || echo unknown)"
    os_kernel="$(uname -sr 2>/dev/null || echo unknown)"
    if [ -r /proc/cpuinfo ]; then
        cpu_cores="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)"
    else
        cpu_cores="$(nproc 2>/dev/null || echo 1)"
    fi
    if [ -r /proc/loadavg ]; then
        load_1m="$(awk '{print $1}' /proc/loadavg)"
    else
        load_1m="0.00"
    fi

    root_login="unknown"
    pass_auth="unknown"
    if [ -r "$sshd_conf" ]; then
        root_login="$(grep -iE '^[[:space:]]*PermitRootLogin[[:space:]]+' "$sshd_conf" | tail -n1 | awk '{print $2}')"
        pass_auth="$(grep -iE '^[[:space:]]*PasswordAuthentication[[:space:]]+' "$sshd_conf" | tail -n1 | awk '{print $2}')"
    fi

    mbf::json::object \
        "hostname=${host}" \
        "os_kernel=${os_kernel}" \
        "cpu_cores:=${cpu_cores}" \
        "load_1m=${load_1m}" \
        "ssh_permit_root_login=${root_login:-unset}" \
        "ssh_password_auth=${pass_auth:-unset}"
}
