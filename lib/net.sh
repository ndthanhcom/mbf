#!/usr/bin/env bash
# @mbf-module: net
# @mbf-rank: •••
# mbf:requires log str
# ==============================================================================
# mbf core library: net
# HTTP/REST client, verified file downloads, IP detection, TCP port & DNS checks
# ==============================================================================

# Perform an HTTP request (GET, POST, PUT, DELETE)
# Usage: mbf::net::request <METHOD> <URL> [BODY] [CONTENT_TYPE]
function mbf::net::request() {
    local method="${1:-GET}"
    local url="$2"
    local body="${3:-}"
    local content_type="${4:-application/json}"
    local timeout="${MBF_HTTP_TIMEOUT:-10}"

    if [ -z "$url" ]; then
        mbf::log::error "mbf::net::request: URL is required"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would HTTP $method $url ${body:+with body: $body}"
        return 0
    fi

    if command -v curl >/dev/null 2>&1; then
        local -a args=(-fsSL --connect-timeout "$timeout" -X "$method")
        [ -n "$body" ] && args+=(-H "Content-Type: $content_type" --data "$body")
        curl "${args[@]}" "$url"
    elif command -v wget >/dev/null 2>&1; then
        if [ -n "$body" ]; then
            wget -qO- --timeout="$timeout" --header="Content-Type: $content_type" --post-data="$body" "$url"
        else
            wget -qO- --timeout="$timeout" "$url"
        fi
    else
        mbf::log::error "mbf::net::request: neither curl nor wget is installed"
        return 1
    fi
}

# Fetch HTTP status code for a URL (e.g. 200, 404, 502)
function mbf::net::status_code() {
    local url="$1"
    local timeout="${2:-5}"
    if mbf::is_dryrun; then
        printf '200\n'
        return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout "$timeout" "$url"
    else
        printf '000\n'
        return 1
    fi
}

# Perform HTTP POST with a JSON payload
function mbf::net::post_json() {
    local url="$1"
    local json_payload="$2"
    mbf::net::request "POST" "$url" "$json_payload" "application/json"
}

# Poll a URL until it returns expected HTTP status code (default: 200)
# Usage: mbf::net::wait_http <url> [timeout_sec] [expected_code]
function mbf::net::wait_http() {
    local url="$1"
    local timeout="${2:-30}"
    local expected="${3:-200}"
    local elapsed=0 code

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would wait up to ${timeout}s for $url -> HTTP $expected"
        return 0
    fi

    while [ "$elapsed" -lt "$timeout" ]; do
        code="$(mbf::net::status_code "$url" 3)"
        if [ "$code" == "$expected" ]; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    mbf::log::error "Timeout (${timeout}s) waiting for $url to return HTTP $expected (last: $code)"
    return 1
}

# Download a file from `<url>` to `<dest_file>` with optional SHA-256 verification
# Usage: mbf::net::download <url> <dest_file> [expected_sha256]
function mbf::net::download() {
    local url="$1"
    local dest="$2"
    local expected_sha="${3:-}"

    if [ -z "$url" ] || [ -z "$dest" ]; then
        mbf::log::error "mbf::net::download: <url> and <dest_file> are required"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would download $url -> $dest"
        return 0
    fi

    mkdir -p "$(dirname "$dest")" 2>/dev/null || true
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest" || return 1
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" "$url" || return 1
    else
        mbf::log::error "mbf::net::download: neither curl nor wget is installed"
        return 1
    fi

    if [ -n "$expected_sha" ]; then
        mbf::str::verify_sha256 "$dest" "$expected_sha" || { rm -f "$dest"; return 1; }
    fi
    return 0
}

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
