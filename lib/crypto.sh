#!/usr/bin/env bash
# mbf:requires log
# ==============================================================================
# mbf core library: crypto
# SHA-256 checksums, HMAC-SHA256 webhook signing, and SSL certificate inspection
# ==============================================================================

# Compute SHA-256 hex digest of a file
# Usage: mbf::crypto::sha256 <file>
function mbf::crypto::sha256() {
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
# Usage: mbf::crypto::verify_sha256 <file> <expected_hex>
function mbf::crypto::verify_sha256() {
    local file="$1"
    local expected="${2,,}"
    local actual
    actual="$(mbf::crypto::sha256 "$file")" || return 1
    actual="${actual,,}"

    if [ "$actual" != "$expected" ]; then
        mbf::log::error "SHA-256 mismatch for $file (expected: $expected, got: $actual)"
        return 1
    fi
    return 0
}

# Compute HMAC-SHA256 signature of `<payload>` using `<secret>`
# Usage: mbf::crypto::hmac_sha256 <secret> <payload>
function mbf::crypto::hmac_sha256() {
    local secret="$1"
    local payload="$2"

    if command -v openssl >/dev/null 2>&1; then
        printf '%s' "$payload" | openssl dgst -sha256 -hmac "$secret" | awk '{print $NF}'
    else
        mbf::log::error "openssl is required for mbf::crypto::hmac_sha256"
        return 1
    fi
}

# Return remaining days before an SSL certificate (PEM file or domain:443) expires
# Usage: mbf::crypto::cert_expiry_days <pem_file_or_domain>
function mbf::crypto::cert_expiry_days() {
    local target="$1"
    local end_date_str end_epoch now_epoch

    if ! command -v openssl >/dev/null 2>&1; then
        mbf::log::error "openssl is required to inspect SSL certificates"
        return 1
    fi

    if [ -f "$target" ]; then
        end_date_str="$(openssl x509 -enddate -noout -in "$target" 2>/dev/null | cut -d= -f2)"
    else
        end_date_str="$( </dev/null openssl s_client -servername "$target" -connect "${target}:443" 2>/dev/null | openssl x509 -enddate -noout 2>/dev/null | cut -d= -f2)"
    fi

    [ -z "$end_date_str" ] && return 1
    end_epoch="$(date -d "$end_date_str" +%s 2>/dev/null)" || return 1
    now_epoch="$(date +%s)"
    printf '%d\n' $(( (end_epoch - now_epoch) / 86400 ))
}
