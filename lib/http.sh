#!/usr/bin/env bash
# mbf:requires log json
# ==============================================================================
# mbf core library: http
# HTTP client (curl/wget), JSON API helpers, and endpoint readiness probes
# ==============================================================================

# Perform an HTTP request
# Usage: mbf::http::request <METHOD> <URL> [BODY] [CONTENT_TYPE]
function mbf::http::request() {
    local method="${1:-GET}"
    local url="$2"
    local body="${3:-}"
    local content_type="${4:-application/json}"
    local timeout="${MBF_HTTP_TIMEOUT:-10}"

    if [ -z "$url" ]; then
        mbf::log::error "mbf::http::request: URL is required"
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
        mbf::log::error "mbf::http::request: neither curl nor wget is installed"
        return 1
    fi
}

# Fetch HTTP status code for a URL (e.g. 200, 404, 502)
function mbf::http::status_code() {
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

# Perform HTTP GET and output response body
function mbf::http::get_json() {
    mbf::http::request "GET" "$1"
}

# Perform HTTP POST with a JSON payload
function mbf::http::post_json() {
    local url="$1"
    local json_payload="$2"
    mbf::http::request "POST" "$url" "$json_payload" "application/json"
}

# Poll a URL until it returns expected HTTP status code (default: 200)
# Usage: mbf::http::wait_ok <url> [timeout_sec] [expected_code]
function mbf::http::wait_ok() {
    local url="$1"
    local timeout="${2:-30}"
    local expected="${3:-200}"
    local elapsed=0 code

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would wait up to ${timeout}s for $url -> HTTP $expected"
        return 0
    fi

    while [ "$elapsed" -lt "$timeout" ]; do
        code="$(mbf::http::status_code "$url" 3)"
        if [ "$code" == "$expected" ]; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    mbf::log::error "Timeout (${timeout}s) waiting for $url to return HTTP $expected (last: $code)"
    return 1
}
