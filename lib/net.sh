#!/usr/bin/env bash
# @mbf-module: net
# mbf:requires log str
# ==============================================================================
# mbf core library: net
# HTTP/REST client (with custom headers), verified file downloads, IP detection,
# TCP port polling & DNS checks
# ==============================================================================

# mbf:state_start
MBF_HTTP_HEADERS=()
MBF_HTTP_TIMEOUT="${MBF_HTTP_TIMEOUT:-10}"
MBF_HTTP_MAX_TIME="${MBF_HTTP_MAX_TIME:-30}"
MBF_HTTP_LAST_STATUS=""
# shellcheck disable=SC2034
MBF_HTTP_LAST_BODY=""
# mbf:state_end

# Register a custom HTTP header for subsequent `mbf::net::request` / `fetch` / `download` calls
# Usage: mbf::net::header_add "Authorization: Bearer ${API_TOKEN}"
function mbf::net::header_add() {
    local header="${1:-}"
    [ -n "$header" ] || return 1
    MBF_HTTP_HEADERS+=("$header")
}

# Register an `Authorization: Bearer <token>` header and redact `<token>` in logs
# Usage: mbf::net::auth_bearer "${API_TOKEN}"
function mbf::net::auth_bearer() {
    local token="${1:-}"
    [ -n "$token" ] || { mbf::log::error "mbf::net::auth_bearer: token is required"; return 1; }
    mbf::log::redact "$token"
    mbf::net::header_add "Authorization: Bearer ${token}"
}

# Register an `Authorization: Basic <base64>` header and redact `<password>` in logs
# Usage: mbf::net::auth_basic "api_user" "${API_PASS}"
function mbf::net::auth_basic() {
    local user="${1:-}"
    local pass="${2:-}"
    [ -n "$user" ] || { mbf::log::error "mbf::net::auth_basic: username is required"; return 1; }
    [ -n "$pass" ] && mbf::log::redact "$pass"
    local encoded
    encoded="$(mbf::str::b64_encode "${user}:${pass}")"
    mbf::net::header_add "Authorization: Basic ${encoded}"
}

# Clear all registered custom HTTP headers
function mbf::net::headers_clear() {
    MBF_HTTP_HEADERS=()
}

# Build an RFC 3986 percent-encoded URL query string from `key=value` pairs
# Usage: mbf::net::build_query "env=prod" "q=hello world"
function mbf::net::build_query() {
    local out="" sep="" pair k v ek ev
    for pair in "$@"; do
        if [[ "$pair" == *"="* ]]; then
            k="${pair%%=*}"
            v="${pair#*=}"
            ek="$(mbf::str::urlencode "$k")"
            ev="$(mbf::str::urlencode "$v")"
            out="${out}${sep}${ek}=${ev}"
        else
            ek="$(mbf::str::urlencode "$pair")"
            out="${out}${sep}${ek}"
        fi
        sep="&"
    done
    printf '%s\n' "$out"
}

# Perform an HTTP request (GET, POST, PUT, DELETE), sending any `MBF_HTTP_HEADERS`
# Usage: mbf::net::request <METHOD> <URL> [BODY] [CONTENT_TYPE]
function mbf::net::request() {
    local method="${1:-GET}"
    local url="${2:-}"
    local body="${3:-}"
    local content_type="${4:-application/json}"
    local timeout="${MBF_HTTP_TIMEOUT:-10}"
    local max_time="${MBF_HTTP_MAX_TIME:-30}"

    if [ -z "$url" ]; then
        mbf::log::error "mbf::net::request: URL is required"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would HTTP $method $url ${body:+with body: $body}"
        return 0
    fi

    local hdr
    if command -v curl >/dev/null 2>&1; then
        local -a args=(-fsSL --connect-timeout "$timeout" --max-time "$max_time" -X "$method")
        for hdr in ${MBF_HTTP_HEADERS[@]+"${MBF_HTTP_HEADERS[@]}"}; do
            args+=(-H "$hdr")
        done
        [ -n "$body" ] && args+=(-H "Content-Type: $content_type" --data "$body")
        curl "${args[@]}" "$url"
    elif command -v wget >/dev/null 2>&1; then
        local -a wargs=(-qO- --timeout="$timeout" --method="$method")
        for hdr in ${MBF_HTTP_HEADERS[@]+"${MBF_HTTP_HEADERS[@]}"}; do
            wargs+=(--header="$hdr")
        done
        [ -n "$body" ] && wargs+=(--header="Content-Type: $content_type" --body-data="$body")
        wget "${wargs[@]}" "$url"
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
        curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout "$timeout" "$url" || true
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

# Perform an HTTP request and capture BOTH status code (`MBF_HTTP_LAST_STATUS`)
# and response body (`MBF_HTTP_LAST_BODY`), including 4xx/5xx error bodies.
# Returns 0 on 2xx status codes, 1 otherwise.
# Usage: mbf::net::fetch <METHOD> <URL> [BODY] [CONTENT_TYPE]
# shellcheck disable=SC2034 # MBF_HTTP_LAST_BODY is an output variable read by callers
function mbf::net::fetch() {
    local method="${1:-GET}"
    local url="${2:-}"
    local body="${3:-}"
    local content_type="${4:-application/json}"
    local timeout="${MBF_HTTP_TIMEOUT:-10}"
    local max_time="${MBF_HTTP_MAX_TIME:-30}"

    MBF_HTTP_LAST_STATUS="000"
    MBF_HTTP_LAST_BODY=""

    if [ -z "$url" ]; then
        mbf::log::error "mbf::net::fetch: URL is required"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would HTTP fetch $method $url ${body:+with body: $body}"
        MBF_HTTP_LAST_STATUS="200"
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        mbf::log::error "mbf::net::fetch: curl is required"
        return 1
    fi

    local hdr raw
    local -a args=(-sSL --connect-timeout "$timeout" --max-time "$max_time" -X "$method")
    for hdr in ${MBF_HTTP_HEADERS[@]+"${MBF_HTTP_HEADERS[@]}"}; do
        args+=(-H "$hdr")
    done
    [ -n "$body" ] && args+=(-H "Content-Type: $content_type" --data "$body")
    args+=(-w $'\n%{http_code}')

    raw="$(curl "${args[@]}" "$url")" || {
        MBF_HTTP_LAST_STATUS="000"
        return 1
    }

    if [[ "$raw" == *$'\n'* ]]; then
        MBF_HTTP_LAST_STATUS="${raw##*$'\n'}"
        MBF_HTTP_LAST_BODY="${raw%$'\n'*}"
    else
        MBF_HTTP_LAST_STATUS="$raw"
        MBF_HTTP_LAST_BODY=""
    fi

    [[ "$MBF_HTTP_LAST_STATUS" =~ ^2[0-9][0-9]$ ]]
}

# Poll a URL until it returns expected HTTP status code (default: 200)
# Usage: mbf::net::wait_http <url> [timeout_sec] [expected_code]
function mbf::net::wait_http() {
    local url="$1"
    local timeout="${2:-30}"
    local expected="${3:-200}"
    local elapsed=0 code="000"

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would wait up to ${timeout}s for $url -> HTTP $expected"
        return 0
    fi

    while [ "$elapsed" -lt "$timeout" ]; do
        code="$(mbf::net::status_code "$url" 3 || echo 000)"
        if [ "$code" == "$expected" ]; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    mbf::log::error "Timeout (${timeout}s) waiting for $url to return HTTP $expected (last: $code)"
    return 1
}

# Download a file from `<url>` to `<dest_file>` atomically with optional SHA-256 verification.
# Writes to a temporary sibling file first so a failed transfer or checksum mismatch
# never leaves a partial file at `<dest_file>`.
# Usage: mbf::net::download <url> <dest_file> [expected_sha256]
function mbf::net::download() {
    local url="${1:-}"
    local dest="${2:-}"
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
    local tmp_dest="${dest}.mbf.part.$$"
    local hdr

    if command -v curl >/dev/null 2>&1; then
        local -a dl_args=(-fsSL)
        for hdr in ${MBF_HTTP_HEADERS[@]+"${MBF_HTTP_HEADERS[@]}"}; do
            dl_args+=(-H "$hdr")
        done
        curl "${dl_args[@]}" "$url" -o "$tmp_dest" || { rm -f "$tmp_dest"; return 1; }
    elif command -v wget >/dev/null 2>&1; then
        local -a wdl_args=(-qO "$tmp_dest")
        for hdr in ${MBF_HTTP_HEADERS[@]+"${MBF_HTTP_HEADERS[@]}"}; do
            wdl_args+=(--header="$hdr")
        done
        wget "${wdl_args[@]}" "$url" || { rm -f "$tmp_dest"; return 1; }
    else
        mbf::log::error "mbf::net::download: neither curl nor wget is installed"
        return 1
    fi

    if [ -n "$expected_sha" ]; then
        if ! mbf::str::verify_sha256 "$tmp_dest" "$expected_sha"; then
            rm -f "$tmp_dest"
            return 1
        fi
    fi

    mv -f "$tmp_dest" "$dest"
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
        curl -fsSL --connect-timeout 4 https://icanhazip.com 2>/dev/null | tr -d '[:space:]' || true
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
        dig +short A "$domain" 2>/dev/null | grep -E '^[0-9.]+$' | head -n 1 || true
    elif command -v nslookup >/dev/null 2>&1; then
        nslookup "$domain" 2>/dev/null | awk '/^Address: / {print $2}' | tail -n 1
    fi
}
