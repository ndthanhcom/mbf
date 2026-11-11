#!/usr/bin/env bash
# @mbf-module: str
# @mbf-rank: ••
# mbf:requires log
# ==============================================================================
# mbf core library: str
# Non-trivial string sanitization, token generation, SHA-256 & HMAC-SHA256
# (Note: Use native Bash `${var,,}` and `${var^^}` for lowercase/uppercase.)
# ==============================================================================

# Strip leading and trailing whitespace from a string
function mbf::str::trim() {
    local s="$*"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s\n' "$s"
}

# Convert string into a URL/filename-safe lowercase slug
function mbf::str::slugify() {
    local s="${*,,}"
    s="$(printf '%s' "$s" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
    printf '%s\n' "$s"
}

# Generate a random alphanumeric string of given length (default: 24)
function mbf::str::random() {
    local len="${1:-24}"
    local out=""
    if [ -r /dev/urandom ]; then
        out="$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom 2>/dev/null | head -c "$len")"
    fi
    if [ "${#out}" -lt "$len" ]; then
        while [ "${#out}" -lt "$len" ]; do
            out="${out}$(printf '%x%x' "$RANDOM" "$RANDOM")"
        done
        out="${out:0:$len}"
    fi
    printf '%s\n' "$out"
}

# Compute SHA-256 hex digest of a file
# Usage: mbf::str::sha256 <file>
function mbf::str::sha256() {
    local file="$1"
    [ -f "$file" ] || return 1

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    else
        mbf::log::error "No SHA-256 tool (sha256sum, shasum, openssl) available"
        return 1
    fi
}

# Verify a file's SHA-256 digest matches `<expected_hex>`
# Usage: mbf::str::verify_sha256 <file> <expected_hex>
function mbf::str::verify_sha256() {
    local file="$1"
    local expected="${2,,}"
    local actual
    actual="$(mbf::str::sha256 "$file")" || return 1
    actual="${actual,,}"

    if [ "$actual" != "$expected" ]; then
        mbf::log::error "SHA-256 mismatch for $file (expected: $expected, got: $actual)"
        return 1
    fi
    return 0
}

# Compute HMAC-SHA256 signature of `<payload>` using `<secret>`
# Usage: mbf::str::hmac_sha256 <secret> <payload>
function mbf::str::hmac_sha256() {
    local secret="$1"
    local payload="$2"

    if command -v openssl >/dev/null 2>&1; then
        printf '%s' "$payload" | openssl dgst -sha256 -hmac "$secret" | awk '{print $NF}'
    else
        mbf::log::error "openssl is required for mbf::str::hmac_sha256"
        return 1
    fi
}
