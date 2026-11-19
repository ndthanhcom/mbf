# Library: `net` — HTTP Client, Checksum Downloads, Ports & DNS

`lib/net.sh` wraps `curl`/`wget` and socket utilities with dry-run awareness, atomic SHA-256 verified file downloads, HTTP health-check polling, TCP port readiness checks, and DNS/IP discovery.

---

## Environment Variables

- `MBF_HTTP_TIMEOUT` — Connection timeout in seconds for `mbf::net::request` (default: `10`).

---

## Function Reference & Examples

### 1. `mbf::net::request <METHOD> <url> [body] [content_type]`
Performs an HTTP `GET`, `POST`, `PUT`, or `DELETE` request using `curl` (or `wget --method` fallback). Respects `MBF_DRYRUN=1`.

```bash
mbf::use net

# Simple GET request
 body="$(mbf::net::request GET "https://api.example.com/v1/version")"

# PUT request with JSON body
mbf::net::request PUT "https://api.example.com/v1/nodes/web01" '{"maintenance":true}'
```

### 2. `mbf::net::post_json <url> <json_payload>`
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

### 8. `mbf::net::header_add "<Header: Value>"` & `mbf::net::headers_clear`
Registers or clears custom HTTP headers (`MBF_HTTP_HEADERS`) sent by subsequent `mbf::net::request`, `mbf::net::post_json`, and `mbf::net::download` calls (supported for both `curl` and `wget`).

```bash
mbf::net::header_add "Authorization: Bearer ${API_TOKEN}"
mbf::net::request "GET" "https://api.example.com/v1/deployments"
mbf::net::headers_clear
```
