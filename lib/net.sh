#!/usr/bin/env bash
# mbf:requires log
# ==============================================================================
# mbf core library: net
# Network IP detection, TCP port checks, and DNS resolution helpers
# ==============================================================================

# Print primary local/private IPv4 address
function mbf::net::private_ip() {
    if command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
        hostname -I | awk '{print $1}'
    elif command -v ip >/dev/null 2>&1; then
        ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}'
    else
        printf '127.0.0.1\n'
    fi
}

# Print public IPv4 address via external echo service
function mbf::net::public_ip() {
    if mbf::is_dryrun; then
        printf '203.0.113.10\n'
        return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 4 https://icanhazip.com 2>/dev/null | tr -d '[:space:]'
        printf '\n'
    fi
}

# Return 0 if TCP port is open on host (defaults to 127.0.0.1)
# Usage: mbf::net::is_port_open <port> [host]
function mbf::net::is_port_open() {
    local port="$1"
    local host="${2:-127.0.0.1}"

    mbf::is_dryrun && return 0

    if command -v nc >/dev/null 2>&1; then
        nc -z -w 2 "$host" "$port" >/dev/null 2>&1
        return $?
    elif command -v ss >/dev/null 2>&1 && [ "$host" == "127.0.0.1" ]; then
        ss -tuln 2>/dev/null | grep -Eq ":${port}([[:space:]]|$)"
        return $?
    else
        (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1
        return $?
    fi
}

# Wait until a TCP port is open (up to timeout_sec)
# Usage: mbf::net::wait_port <port> [host] [timeout_sec]
function mbf::net::wait_port() {
    local port="$1"
    local host="${2:-127.0.0.1}"
    local timeout="${3:-30}"
    local elapsed=0

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would wait for ${host}:${port}"
        return 0
    fi

    while [ "$elapsed" -lt "$timeout" ]; do
        if mbf::net::is_port_open "$port" "$host"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    mbf::log::error "Timeout (${timeout}s) waiting for TCP port ${host}:${port}"
    return 1
}

# Resolve a domain name to its IPv4 address
# Usage: mbf::net::resolve_dns <domain>
function mbf::net::resolve_dns() {
    local domain="$1"
    if command -v getent >/dev/null 2>&1; then
        getent ahostsv4 "$domain" 2>/dev/null | awk 'NR==1 {print $1}'
    elif command -v dig >/dev/null 2>&1; then
        dig +short A "$domain" 2>/dev/null | grep -E '^[0-9.]+$' | head -n 1
    elif command -v nslookup >/dev/null 2>&1; then
        nslookup "$domain" 2>/dev/null | awk '/^Address: / {print $2}' | tail -n 1
    fi
}
