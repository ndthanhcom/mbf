#!/usr/bin/env bash
# @mbf-module: str
# mbf:requires log
# ==============================================================================
# mbf core library: str
# Non-trivial string sanitization, web encoding, identifiers, delimiters,
# regex escaping, token generation, SHA-256 & HMAC-SHA256
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
        # Read a bounded chunk with `dd` first so `tr` always hits EOF and never
        # hangs on infinite `/dev/urandom` when SIGPIPE is ignored (e.g. CI runners).
        out="$(dd if=/dev/urandom bs=64 count=8 2>/dev/null | LC_ALL=C tr -dc 'a-zA-Z0-9' | head -c "$len" || true)"
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

# RFC 3986 percent-encode a string in pure Bash (safe for query params & DSN passwords)
# Usage: mbf::str::urlencode "p@ss/w0rd?a=1&b=2"
function mbf::str::urlencode() {
    local LC_ALL=C
    local s="${1:-}" i c out="" hex
    local len="${#s}"
    for ((i = 0; i < len; i++)); do
        c="${s:i:1}"
        case "$c" in
            [a-zA-Z0-9._~-]) out+="$c" ;;
            *)
                printf -v hex '%%%02X' "'$c"
                out+="$hex"
                ;;
        esac
    done
    printf '%s\n' "$out"
}

# Decode a URL-encoded string (`%XX` and `+`) in pure Bash
# Usage: mbf::str::urldecode "hello+world%21"
function mbf::str::urldecode() {
    local s="${1:-}"
    s="${s//\\/\\\\}"
    s="${s//+/ }"
    s="${s//%/\\x}"
    printf '%b\n' "$s"
}

# Portable single-line Base64 encoding (avoids GNU `-w0` vs macOS BSD line-wrap differences)
# Usage: mbf::str::b64_encode "user:pass"
function mbf::str::b64_encode() {
    printf '%s' "${1:-}" | base64 | tr -d '\r\n'
    printf '\n'
}

# Portable Base64 decoding (handles GNU `base64 -d` and macOS BSD `base64 -D`)
# Usage: mbf::str::b64_decode "dXNlcjpwYXNz"
function mbf::str::b64_decode() {
    local encoded="${1:-}"
    if printf '%s' "$encoded" | base64 -d 2>/dev/null; then
        return 0
    fi
    printf '%s' "$encoded" | base64 -D 2>/dev/null
}

# Generate a lowercase RFC 4122 UUIDv4 portably across Linux, macOS, and Windows Git Bash
# Usage: mbf::str::uuid
function mbf::str::uuid() {
    if [ -r /proc/sys/kernel/random/uuid ]; then
        tr '[:upper:]' '[:lower:]' < /proc/sys/kernel/random/uuid
        return 0
    fi
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr '[:upper:]' '[:lower:]'
        return 0
    fi
    local hex=""
    if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
        hex="$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n\r')"
    else
        while [ "${#hex}" -lt 32 ]; do
            hex="${hex}$(printf '%04x' "$RANDOM")"
        done
    fi
    # Set RFC 4122 version (4) and variant (8/9/a/b -> a)
    printf '%s-%s-4%s-a%s-%s\n' \
        "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" "${hex:17:3}" "${hex:20:12}"
}

# Mask the middle of a sensitive string for safe human display
# Usage: mbf::str::mask "ghp_1234567890abcd" [head=4] [tail=4] [mask_char=*]
function mbf::str::mask() {
    local s="${1:-}"
    local head="${2:-4}"
    local tail="${3:-4}"
    local ch="${4:-*}"
    local len="${#s}"
    [ "$len" -eq 0 ] && { printf '\n'; return 0; }

    local mask_len i masked=""
    if [ "$len" -le $((head + tail)) ]; then
        for ((i = 0; i < len; i++)); do masked+="$ch"; done
        printf '%s\n' "$masked"
        return 0
    fi

    mask_len=$((len - head - tail))
    for ((i = 0; i < mask_len; i++)); do masked+="$ch"; done
    printf '%s%s%s\n' "${s:0:head}" "$masked" "${s:len-tail:tail}"
}

# Convert CamelCase, kebab-case, or prose text into lowercase `snake_case` identifier
# Usage: mbf::str::snake "MyAppService-v2"
function mbf::str::snake() {
    local s="$*"
    s="$(printf '%s' "$s" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g; s/([A-Z]+)([A-Z][a-z])/\1_\2/g')"
    s="${s,,}"
    s="$(printf '%s' "$s" | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//')"
    printf '%s\n' "$s"
}

# Join arguments with a single- or multi-character delimiter
# Usage: mbf::str::join ", " "web01" "web02" "web03"
function mbf::str::join() {
    local sep="${1:-}"
    shift 1 2>/dev/null || true
    if [ $# -eq 0 ]; then
        printf '\n'
        return 0
    fi
    local out="$1" item
    shift 1
    for item in "$@"; do
        out="${out}${sep}${item}"
    done
    printf '%s\n' "$out"
}

# Split `<string>` on a literal delimiter into a caller-supplied Bash array (no globbing)
# Usage: mbf::str::split ", " "a, b, c" MY_ARRAY
function mbf::str::split() {
    local sep="${1:-}"
    local rest="${2:-}"
    local -n _mbf_split_ref="$3"
    _mbf_split_ref=()

    if [ -z "$rest" ]; then
        return 0
    fi
    if [ -z "$sep" ]; then
        _mbf_split_ref=("$rest")
        return 0
    fi

    while [[ "$rest" == *"$sep"* ]]; do
        _mbf_split_ref+=("${rest%%"$sep"*}")
        rest="${rest#*"$sep"}"
    done
    _mbf_split_ref+=("$rest")
}

# Return 0 if `<needle>` exactly matches any of the remaining items, 1 otherwise
# Safe under `set -u` for empty lists / missing arguments.
# Usage: mbf::str::in_list "prod" "dev" "staging" "prod"
function mbf::str::in_list() {
    [ $# -ge 2 ] || return 1
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [ "$item" == "$needle" ] && return 0
    done
    return 1
}

# Truncate `<string>` to `<max_len>` characters, appending `[suffix]` (default: `...`)
# Usage: mbf::str::truncate "Long deployment message" 12
function mbf::str::truncate() {
    local s="${1:-}"
    local max_len="${2:-80}"
    local suffix="${3:-...}"

    if [ "${#s}" -le "$max_len" ]; then
        printf '%s\n' "$s"
        return 0
    fi
    local suf_len="${#suffix}"
    if [ "$max_len" -le "$suf_len" ]; then
        printf '%s\n' "${s:0:max_len}"
        return 0
    fi
    printf '%s%s\n' "${s:0:max_len-suf_len}" "$suffix"
}

# Extract the substring between the first literal `<start>` and `<end>` markers
# Returns 1 when either marker is not found.
# Usage: mbf::str::between "tag=[v1.2.3]" "[" "]"
function mbf::str::between() {
    local s="${1:-}"
    local start="${2:-}"
    local end="${3:-}"

    [[ "$s" == *"$start"* ]] || return 1
    local after="${s#*"$start"}"
    [[ "$after" == *"$end"* ]] || return 1
    printf '%s\n' "${after%%"$end"*}"
}

# Escape ERE regex metacharacters in pure Bash so `<string>` can be embedded safely in `grep -E` / `sed -E`
# Usage: mbf::str::escape_regex "10.0.0.1 (prod+1)"
function mbf::str::escape_regex() {
    local s="${1:-}" i c out=""
    local len="${#s}"
    for ((i = 0; i < len; i++)); do
        c="${s:i:1}"
        case "$c" in
            '['|']'|'.'|'^'|'$'|'*'|'+'|'?'|'('|')'|'{'|'}'|'|'|'/'|'\')
                out+="\\${c}"
                ;;
            *)
                out+="$c"
                ;;
        esac
    done
    printf '%s\n' "$out"
}
