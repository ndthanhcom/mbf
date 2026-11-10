#!/usr/bin/env bash
# mbf:requires log exec os
# ==============================================================================
# mbf plugin: firewall
# Unified Firewall Configuration Manager (UFW, Firewalld, Iptables)
# ==============================================================================

# Detect active or installed firewall backend (ufw, firewalld, iptables)
function mbf::firewall::backend() {
    if [ -n "${MBF_FIREWALL_BACKEND:-}" ]; then
        printf '%s\n' "$MBF_FIREWALL_BACKEND"
        return 0
    elif command -v ufw >/dev/null 2>&1; then
        printf 'ufw\n'
    elif command -v firewall-cmd >/dev/null 2>&1; then
        printf 'firewalld\n'
    elif command -v iptables >/dev/null 2>&1; then
        printf 'iptables\n'
    else
        printf 'none\n'
        return 1
    fi
}

# Allow incoming traffic on a port/protocol
# Usage: mbf::firewall::allow_port <port> [tcp|udp]
function mbf::firewall::allow_port() {
    local port="$1"
    local proto="${2:-tcp}"
    local backend
    backend="$(mbf::firewall::backend)"

    case "$backend" in
        ufw)       mbf::exec::sudo ufw allow "${port}/${proto}" ;;
        firewalld) mbf::exec::sudo firewall-cmd --permanent --add-port="${port}/${proto}" && mbf::exec::sudo firewall-cmd --reload ;;
        iptables)  mbf::exec::sudo iptables -A INPUT -p "$proto" --dport "$port" -j ACCEPT ;;
        *)         mbf::log::error "No supported firewall backend found"; return 1 ;;
    esac
}

# Deny incoming traffic on a port/protocol
# Usage: mbf::firewall::deny_port <port> [tcp|udp]
function mbf::firewall::deny_port() {
    local port="$1"
    local proto="${2:-tcp}"
    local backend
    backend="$(mbf::firewall::backend)"

    case "$backend" in
        ufw)       mbf::exec::sudo ufw deny "${port}/${proto}" ;;
        firewalld) mbf::exec::sudo firewall-cmd --permanent --remove-port="${port}/${proto}" && mbf::exec::sudo firewall-cmd --reload ;;
        iptables)  mbf::exec::sudo iptables -A INPUT -p "$proto" --dport "$port" -j DROP ;;
        *)         mbf::log::error "No supported firewall backend found"; return 1 ;;
    esac
}

# Enable safe baseline firewall rules (always allowing SSH + HTTP/HTTPS first to prevent lockout)
# Usage: mbf::firewall::enable_baseline [ssh_port]
function mbf::firewall::enable_baseline() {
    local ssh_port="${1:-22}"
    local backend
    backend="$(mbf::firewall::backend)"

    mbf::firewall::allow_port "$ssh_port" "tcp" || return 1
    mbf::firewall::allow_port "80" "tcp" || return 1
    mbf::firewall::allow_port "443" "tcp" || return 1

    if [ "$backend" == "ufw" ]; then
        mbf::exec::sudo ufw default deny incoming
        mbf::exec::sudo ufw default allow outgoing
        mbf::exec::sudo ufw --force enable
    fi
    mbf::log::ok "Baseline firewall rules enabled (SSH:$ssh_port, HTTP:80, HTTPS:443)"
}
