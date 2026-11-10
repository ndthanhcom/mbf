#!/usr/bin/env bash
# mbf:requires log exec
# ==============================================================================
# mbf core library: service
# Cross-distro system service controller (systemctl, service, rc-service)
# ==============================================================================

function _mbf_service_ctl() {
    local action="$1"
    local svc="$2"

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would $action service '$svc'"
        return 0
    fi

    if command -v systemctl >/dev/null 2>&1; then
        mbf::exec::sudo systemctl "$action" "$svc"
    elif command -v service >/dev/null 2>&1; then
        mbf::exec::sudo service "$svc" "$action"
    elif command -v rc-service >/dev/null 2>&1; then
        mbf::exec::sudo rc-service "$svc" "$action"
    else
        mbf::log::error "No supported service manager (systemctl/service/rc-service) found"
        return 1
    fi
}

function mbf::service::start() {
    _mbf_service_ctl "start" "$1"
}

function mbf::service::stop() {
    _mbf_service_ctl "stop" "$1"
}

function mbf::service::restart() {
    _mbf_service_ctl "restart" "$1"
}

function mbf::service::reload() {
    _mbf_service_ctl "reload" "$1"
}

function mbf::service::enable() {
    local svc="$1"
    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would enable service '$svc'"
        return 0
    fi
    if command -v systemctl >/dev/null 2>&1; then
        mbf::exec::sudo systemctl enable "$svc"
    elif command -v rc-update >/dev/null 2>&1; then
        mbf::exec::sudo rc-update add "$svc" default
    fi
}

# Return 0 if service is currently active/running
function mbf::service::is_active() {
    local svc="$1"
    mbf::is_dryrun && return 0
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet "$svc"
    elif command -v service >/dev/null 2>&1; then
        service "$svc" status >/dev/null 2>&1
    else
        pgrep -x "$svc" >/dev/null 2>&1
    fi
}

# Ensure service is enabled and running (starts it if stopped)
function mbf::service::ensure_running() {
    local svc="$1"
    mbf::service::enable "$svc"
    if ! mbf::service::is_active "$svc"; then
        mbf::service::start "$svc"
    fi
}
