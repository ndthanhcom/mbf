# Library: `str` — String Sanitization, Random Tokens & Cryptographic Hashes

`lib/str.sh` includes only non-trivial string sanitization, token generation, and SHA-256 / HMAC-SHA256 primitives.

> [!NOTE]
> **Native-First Rule**: For simple case conversion or substring replacement, use native Bash 4+ parameter expansion directly (`${var,,}` for lowercase, `${var^^}` for uppercase, `${var//old/new}` for replacement).

---

## Function Reference & Examples

### 1. `mbf::str::trim <string>`
Strips all leading and trailing whitespace (spaces, tabs, newlines) from `<string>` using pure Bash parameter expansion.

```bash
mbf::use str

clean="$(mbf::str::trim "   production-cluster-01   ")"
echo "[${clean}]"
# Output: [production-cluster-01]
```

### 2. `mbf::str::slugify <string>`
Converts `<string>` into a URL- and filename-safe lowercase slug (`a-z0-9` separated by single hyphens).

```bash
slug="$(mbf::str::slugify "Client Store (Prod #01)!")"
echo "$slug"
# Output: client-store-prod-01
```

### 3. `mbf::str::random [length]`
Generates a cryptographically random alphanumeric string (`a-zA-Z0-9`) of `[length]` characters (default: `24`) from `/dev/urandom` (`pipefail`-safe).

```bash
db_pass="$(mbf::str::random 32)"
echo "Generated 32-char password: ${db_pass}"
```

### 4. `mbf::str::sha256 <file>`
Computes the 64-character lowercase hexadecimal SHA-256 digest of `<file>` across `sha256sum` (Linux/Git Bash), `shasum -a 256` (macOS), or `openssl dgst -sha256`.

```bash
digest="$(mbf::str::sha256 "/var/backups/db_20261116.sql.gz")"
echo "SHA-256: ${digest}"
```

### 5. `mbf::str::verify_sha256 <file> <expected_hex>`
Verifies that `<file>`'s SHA-256 digest matches `<expected_hex>` (case-insensitive). Logs an error and returns `1` on mismatch.

```bash
mbf::str::verify_sha256 "/tmp/installer.tar.gz" "$EXPECTED_SHA256" || mbf::die "Checksum verification failed!"
```

### 6. `mbf::str::hmac_sha256 <secret> <payload>`
Computes an HMAC-SHA256 hex signature of `<payload>` using `<secret>` via `openssl`. Used for signing SaaS and webhook payloads.

```bash
sig="$(mbf::str::hmac_sha256 "$WEBHOOK_SECRET" "job_42:completed:2026-11-16T10:00:00Z")"
echo "X-MBF-Signature: ${sig}"
```

### 7. `mbf::str::urlencode <string>` & `mbf::str::urldecode <string>`
Pure-Bash RFC 3986 percent-encoding and decoding (safe for `curl` query params and special characters in DB DSN passwords).

```bash
enc="$(mbf::str::urlencode "p@ss/w0rd?a=1&b=2")"
# Output: p%40ss%2Fw0rd%3Fa%3D1%26b%3D2
mbf::str::urldecode "$enc"
```

### 8. `mbf::str::b64_encode <string>` & `mbf::str::b64_decode <string>`
Portable single-line Base64 encoding and decoding across GNU Linux (`base64 -d`), macOS BSD (`base64 -D`), Alpine/BusyBox, and Windows Git Bash (never wraps lines at 76 chars).

```bash
auth="$(mbf::str::b64_encode "admin:s3cr3t")"
mbf::str::b64_decode "$auth"
```

### 9. `mbf::str::uuid`
Generates a lowercase RFC 4122 UUIDv4 portably across Linux (`/proc/sys/kernel/random/uuid`), macOS (`uuidgen`), and `/dev/urandom` fallback.

```bash
job_id="$(mbf::str::uuid)"
```

### 10. `mbf::str::mask <string> [head=4] [tail=4] [mask_char=*]`
Masks the middle of a sensitive token or key for safe human debugging without exposing the full secret.

```bash
mbf::str::mask "ghp_1234567890abcd" 4 4
# Output: ghp_**********abcd
```

### 11. `mbf::str::snake <string>`
Converts `CamelCase`, `kebab-case`, or prose text into a lowercase `snake_case` identifier (complements `slugify`).

```bash
mbf::str::snake "MyAppService-v2"
# Output: my_app_service_v2
```

### 12. `mbf::str::join <sep> [items...]`, `mbf::str::split <sep> <string> <out_array>` & `mbf::str::in_list <needle> [items...]`
Joins arguments with a single- or multi-character delimiter, safely splits a string into a Bash array without wildcard globbing (`*`) or `IFS` side-effects, or checks exact membership against a list/array (returns `0` on match, `1` otherwise).

```bash
csv="$(mbf::str::join ", " "web01" "web02" "web03")"
# Output: web01, web02, web03

declare -a hosts=()
mbf::str::split ", " "$csv" hosts

if mbf::str::in_list "web02" "${hosts[@]}"; then
    mbf::log::info "web02 is in target pool"
fi
```

### 13. `mbf::str::truncate <string> <max_len> [suffix=...]`
Truncates `<string>` to `<max_len>` characters, appending `[suffix]` (default: `...`).

```bash
mbf::str::truncate "Deploying release v2.4.0 to production" 20
# Output: Deploying release...
```

### 14. `mbf::str::between <string> <start> <end>`
Extracts the literal substring between the first `<start>` and `<end>` markers (returns `1` if either marker is absent).

```bash
mbf::str::between "release=[v1.2.3]" "[" "]"
# Output: v1.2.3
```

### 15. `mbf::str::escape_regex <string>`
Escapes ERE regex metacharacters so `<string>` can be embedded safely in `grep -E` or `sed -E`.

```bash
pat="$(mbf::str::escape_regex "10.0.0.1 (prod+1)")"
# Output: 10\.0\.0\.1 \(prod\+1\)
```
