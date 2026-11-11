#!/usr/bin/env bash
# @mbf-module: config
# @mbf-rank: •••
# mbf:requires log
# ==============================================================================
# mbf core library: config
# Safe key-value, line, and block-based configuration file manipulation + backup
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

# Modify or set key's value in a `key = value` config file (creates key if missing)
# Usage: mbf::config::set <file> <key> <new_value>
function mbf::config::set() {
    local file="$1"
    local key="$2"
    local val="$3"
    [ -f "$file" ] || return 1
    mbf::is_dryrun && return 0

    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null; then
        local esc_key esc_val
        esc_key="$(_mbf_sed_escape_pattern "$key")"
        esc_val="$(_mbf_sed_escape_replacement "$val")"
        sed -i -e "\|$esc_key| s|=.*|= $esc_val|" "$file"
    else
        printf '%s = %s\n' "$key" "$val" >> "$file"
    fi
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
    [ -f "$file" ] || { mbf::is_dryrun || touch "$file"; }
    if [ -f "$file" ] && grep -Fqx "$line" "$file" 2>/dev/null; then
        return 0
    fi
    mbf::config::insert "$file" "$line"
}

# Idempotently manage a named multi-line block in a config file
# Usage: mbf::config::ensure_block <file> <block_id> <content>
function mbf::config::ensure_block() {
    local file="$1"
    local block_id="$2"
    local content="$3"
    local start_mark="# BEGIN MBF:${block_id}"
    local end_mark="# END MBF:${block_id}"

    mbf::is_dryrun && return 0
    [ -f "$file" ] || touch "$file"

    if grep -Fqx "$start_mark" "$file" 2>/dev/null; then
        local tmp_f="${file}.mbf.blk.$$"
        awk -v s="$start_mark" -v e="$end_mark" '
            $0 == s { skip = 1; next }
            $0 == e { skip = 0; next }
            !skip { print }
        ' "$file" > "$tmp_f" && mv -f "$tmp_f" "$file"
    fi

    printf '%s\n%s\n%s\n' "$start_mark" "$content" "$end_mark" >> "$file"
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

# Create a `.mbf.bak` backup of a config file before editing
# Usage: mbf::config::backup /etc/ssh/sshd_config
function mbf::config::backup() {
    local file="$1"
    [ -f "$file" ] || return 1
    mbf::is_dryrun && return 0
    cp -p "$file" "${file}.mbf.bak"
}

# Restore a config file from its `.mbf.bak` backup
# Usage: mbf::config::rollback /etc/ssh/sshd_config
function mbf::config::rollback() {
    local file="$1"
    if [ ! -f "${file}.mbf.bak" ]; then
        mbf::log::error "mbf::config::rollback: no backup found for $file"
        return 1
    fi
    mbf::is_dryrun && return 0
    mv -f "${file}.mbf.bak" "$file"
    mbf::log::warn "Rolled back $file from backup"
}
