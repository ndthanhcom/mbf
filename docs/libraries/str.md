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
