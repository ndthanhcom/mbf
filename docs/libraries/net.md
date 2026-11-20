# Library: `net` — HTTP Client, Checksum Downloads, Ports & DNS

`lib/net.sh` wraps `curl`/`wget` and socket utilities with dry-run awareness, atomic SHA-256 verified file downloads, HTTP health-check polling, TCP port readiness checks, and DNS/IP discovery.

---

## Environment & State Variables

- `MBF_HTTP_TIMEOUT` — Connection timeout in seconds for `mbf::net::request` / `fetch` (default: `10`).
- `MBF_HTTP_MAX_TIME` — Total request timeout in seconds (default: `30`).
- `MBF_HTTP_LAST_STATUS` / `MBF_HTTP_LAST_BODY` — Populated by `mbf::net::fetch` with the HTTP status code and response body (including `4xx`/`5xx` error payloads).

---

## Function Reference & Examples

### 1. `mbf::net::request <METHOD> <url> [body] [content_type]` & `mbf::net::get <url>`
Performs an HTTP `GET`, `POST`, `PUT`, or `DELETE` request using `curl` (or `wget --method` fallback). Respects `MBF_DRYRUN=1`. `mbf::net::get <url>` is a shorthand for `mbf::net::request GET <url>`.

```bash
mbf::use net

# Simple GET request
body="$(mbf::net::get "https://api.example.com/v1/version")"

# PUT request with JSON body
mbf::net::request PUT "https://api.example.com/v1/nodes/web01" '{"maintenance":true}'
```

### 2. `mbf::net::fetch <METHOD> <url> [body] [content_type]`
Captures **both** the HTTP status code (`MBF_HTTP_LAST_STATUS`) and response body (`MBF_HTTP_LAST_BODY`) in one call — unlike `request`, it does not discard `4xx`/`5xx` error bodies. Returns `0` on `2xx` status codes and `1` otherwise.

```bash
if ! mbf::net::fetch POST "https://api.example.com/v1/deploys" '{"tag":"v2.0.0"}'; then
    mbf::log::error "Deploy API failed (HTTP ${MBF_HTTP_LAST_STATUS}): ${MBF_HTTP_LAST_BODY}"
    exit 1
fi
printf 'Created deploy: %s\n' "$MBF_HTTP_LAST_BODY"
```

### 3. `mbf::net::post_json <url> <json_payload>`
Convenience wrapper around `mbf::net::request POST <url> <json_payload> "application/json"`.

```bash
mbf::net::post_json "https://hooks.example.com/deploy" '{"release":"v2.1.0","status":"ok"}'
```

### 3. `mbf::net::status_code <url> [timeout_sec]`
Prints the 3-digit HTTP status code (`200`, `404`, `502`, or `000` on connection error). Returns `200` in dry-run mode.

```bash
code="$(mbf::net::status_code "https://shop.example.com/health_check.php" 5)"
if [ "$code" != "200" ]; then
    mbf::log::error "Health check returned HTTP ${code}"
fi
```

### 4. `mbf::net::wait_http <url> [timeout_sec] [expected_code]`
Polls `<url>` once per second until it returns `[expected_code]` (default: `200`) or `[timeout_sec]` (default: `30`) elapses.

```bash
# Wait up to 45 seconds for the storefront to return HTTP 200 after restart
mbf::net::wait_http "https://shop.example.com/health_check.php" 45 200 || exit 1
```

### 5. `mbf::net::download <url> <dest_file> [expected_sha256]`
Downloads `<url>` to a temporary sibling file first, optionally verifies its SHA-256 checksum against `[expected_sha256]`, and atomically renames it to `<dest_file>`. A failed download or checksum mismatch never leaves a partial or corrupted file behind.

```bash
# Download with SHA-256 verification
mbf::net::download \
    "https://releases.example.com/agent-v1.0.tar.gz" \
    "/tmp/agent-v1.0.tar.gz" \
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
```

### 6. `mbf::net::is_port_open <port> [host]` & `mbf::net::wait_port <port> [host] [timeout_sec]`
Checks whether a TCP port is accepting connections (using `nc`, `ss`, or `/dev/tcp`), or polls once per second until the port opens.

```bash
# Check if local Redis port is open right now
if mbf::net::is_port_open 6379 "127.0.0.1"; then
    mbf::log::info "Redis is listening on 6379"
fi

# Wait up to 60 seconds for MySQL container port 3306 to become ready
mbf::net::wait_port 3306 "127.0.0.1" 60 || mbf::die "MySQL failed to start within 60s"
```

### 7. `mbf::net::private_ip`, `mbf::net::public_ip`, & `mbf::net::resolve_dns <domain>`
- `private_ip`: Prints the host's primary local IPv4 address.
- `public_ip`: Queries `https://icanhazip.com` for the server's public IPv4 address.
- `resolve_dns`: Resolves `<domain>` to its IPv4 address via `getent`, `dig`, or `nslookup`.

```bash
printf 'Private IP : %s\n' "$(mbf::net::private_ip)"
printf 'Public IP  : %s\n' "$(mbf::net::public_ip)"
printf 'Domain IP  : %s\n' "$(mbf::net::resolve_dns "shop.example.com")"
```

### 8. `mbf::net::header_add`, `auth_bearer`, `auth_basic` & `headers_clear`
Manages custom HTTP headers (`MBF_HTTP_HEADERS`) sent by subsequent `request`, `get`, `post_json`, `fetch`, and `download` calls:
- `mbf::net::header_add "<Header: Value>"` — Add a raw HTTP header.
- `mbf::net::auth_bearer "<token>"` — Add `Authorization: Bearer <token>` and auto-redact `<token>` in logs.
- `mbf::net::auth_basic "<user>" "<pass>"` — Base64-encode credentials into `Authorization: Basic ...` and auto-redact `<pass>`.
- `mbf::net::headers_clear` — Clear all registered headers.

```bash
mbf::net::auth_bearer "${API_TOKEN}"
mbf::net::get "https://api.example.com/v1/deployments"
mbf::net::headers_clear
```

### 9. `mbf::net::build_query "k1=v1" "k2=v2" ...`
Builds an RFC 3986 percent-encoded URL query string using `mbf::str::urlencode`.

```bash
qs="$(mbf::net::build_query "env=prod" "q=hello world" "tag=v1.2+rc1")"
mbf::net::get "https://api.example.com/v1/search?${qs}"
# -> https://api.example.com/v1/search?env=prod&q=hello%20world&tag=v1.2%2Brc1
```

### 10. `mbf::net::tls_days_left <host> [port=443]`
Prints the number of days remaining until `<host>`'s TLS certificate expires (returns `90` in dry-run mode).

```bash
days="$(mbf::net::tls_days_left "shop.example.com")"
if [ "$days" -lt 14 ]; then
    mbf::log::warn "TLS certificate expires in ${days} days!"
fi
```
