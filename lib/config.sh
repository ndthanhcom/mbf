#!/usr/bin/env bash
# mbf:requires log
# ==============================================================================
# mbf core library: config
# Safe key-value and line-based configuration file manipulation (direct sed, no eval)
# ==============================================================================

# Escape string for sed regex pattern (using | delimiter)
function _mbf_sed_escape_pattern() {
    printf '%s' "$1" | sed -e 's/[][\/.^$*|]/\\&/g'
}

# Escape string for sed replacement (using | delimiter)
function _mbf_sed_escape_replacement() {
    printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'
}

# Read config value by key from a `key = value` or `key=value` file
# Usage: mbf::config::get <file> <key>
function mbf::config::get() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return 1
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" | tail -n 1 | sed -E 's/^[^=]*=[[:space:]]*//'
}

# Modify existing key's value in a `key = value` config file
# Usage: mbf::config::set <file> <key> <new_value>
function mbf::config::set() {
    local file="$1"
    local key="$2"
    local val="$3"
    [ -f "$file" ] || return 1
    mbf::is_dryrun && return 0

    local esc_key esc_val
    esc_key="$(_mbf_sed_escape_pattern "$key")"
    esc_val="$(_mbf_sed_escape_replacement "$val")"
    sed -i -e "\|$esc_key| s|=.*|= $esc_val|" "$file"
}

# Append a line to the end of a config file
# Usage: mbf::config::insert <file> <line>
function mbf::config::insert() {
    local file="$1"
    shift
    [ -f "$file" ] || return 1
    mbf::is_dryrun && return 0
    printf '%s\n' "$*" >> "$file"
}

# Idempotently ensure an exact line exists in a config file (creates file if missing)
# Usage: mbf::config::ensure <file> <line>
function mbf::config::ensure() {
    local file="$1"
    shift
    local line="$*"
    [ -f "$file" ] || touch "$file"
    if grep -Fqx "$line" "$file" 2>/dev/null; then
        return 0
    fi
    mbf::config::insert "$file" "$line"
}

# Delete lines matching pattern from a file
# Usage: mbf::config::delete_line <file> <pattern>
function mbf::config::delete_line() {
    local file="$1"
    local match="$2"
    [ -f "$file" ] || return 1
    mbf::is_dryrun && return 0

    local esc_match
    esc_match="$(_mbf_sed_escape_pattern "$match")"
    sed -i "\|$esc_match|d" "$file"
}

# Replace entire line matching pattern with new line content
# Usage: mbf::config::replace_line <file> <pattern> <new_line>
function mbf::config::replace_line() {
    local file="$1"
    local match="$2"
    shift 2
    [ -f "$file" ] || return 1
    mbf::is_dryrun && return 0

    local esc_match esc_rep
    esc_match="$(_mbf_sed_escape_pattern "$match")"
    esc_rep="$(_mbf_sed_escape_replacement "$*")"
    sed -i "s|.*${esc_match}.*|${esc_rep}|" "$file"
}

# Replace all occurrences of a substring in a file (supports slashes/paths safely)
# Usage: mbf::config::replace_text <file> <search> <replacement>
function mbf::config::replace_text() {
    local file="$1"
    local match="$2"
    shift 2
    [ -f "$file" ] || return 1
    mbf::is_dryrun && return 0

    local esc_match esc_rep
    esc_match="$(_mbf_sed_escape_pattern "$match")"
    esc_rep="$(_mbf_sed_escape_replacement "$*")"
    sed -i "s|${esc_match}|${esc_rep}|g" "$file"
}

# Print line number of the first occurrence of fixed text in a file; returns 1 if not found
# Usage: mbf::config::line_number <file> <pattern>
function mbf::config::line_number() {
    local file="$1"
    shift
    [ -f "$file" ] || return 1

    local ln
    ln="$(grep -m1 -n -F "$*" "$file" | cut -d: -f1)"
    if [ -n "$ln" ]; then
        printf '%s\n' "$ln"
        return 0
    fi
    return 1
}

# Append a line immediately after the given line number
# Usage: mbf::config::append_after_line <file> <line_number> <text>
function mbf::config::append_after_line() {
    local file="$1"
    local ln="$2"
    shift 2
    [ -f "$file" ] || return 1
    mbf::is_dryrun && return 0

    local esc_text
    esc_text="$(_mbf_sed_escape_replacement "$*")"
    sed -i "${ln}a ${esc_text}" "$file"
}
