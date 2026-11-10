#!/usr/bin/env bash
# ==============================================================================
# mbf core library: str
# String manipulation, input sanitization/validation, and random token generation
# ==============================================================================

function mbf::str::trim() {
    local s="$*"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s\n' "$s"
}

function mbf::str::lower() {
    printf '%s\n' "${*,,}"
}

function mbf::str::upper() {
    printf '%s\n' "${*^^}"
}

function mbf::str::slugify() {
    local s="${*,,}"
    s="$(printf '%s' "$s" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
    printf '%s\n' "$s"
}

function mbf::str::is_alnum() {
    [[ -n "${1:-}" && "$1" =~ ^[a-zA-Z0-9_]+$ ]]
}

function mbf::str::is_domain() {
    [[ -n "${1:-}" && "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

function mbf::str::is_ip() {
    local ip="${1:-}"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS='.' oct
    for oct in $ip; do
        [ "$oct" -le 255 ] 2>/dev/null || return 1
    done
    return 0
}

function mbf::str::is_email() {
    [[ -n "${1:-}" && "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
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
