#!/usr/bin/env bash
# @mbf-module: config
# @mbf-rank: •••
# mbf:requires log
# ==============================================================================
# mbf core library: config
# Safe key-value, directive, line and block-based config file editing + backup
#
# Implementation Notes:
#   - All matching is LITERAL (no regex): keys, patterns and replacement text are
#     handed to `awk` through environment variables (`ENVIRON[...]`), so `/`, `&`,
#     `|`, `.`, `*`, `\` and quotes never need escaping and behave identically on
#     GNU awk, mawk, BusyBox and macOS BSD awk.
#   - Files are rewritten through `_mbf_replace_file` (framework.sh), which keeps
#     the original mode/owner (e.g. a 600 secrets file stays 600) and follows symlinks.
#   - Commented lines (`# ...`, `; ...`) are never treated as `key = value` entries.
# ==============================================================================

# Read config value by key from a `key = value` or `key=value` file (last match wins).
# Returns 1 when the file or key does not exist.
# Usage: mbf::config::get <file> <key>
function mbf::config::get() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return 1
    MBF_K="$key" awk '
        BEGIN { k = ENVIRON["MBF_K"] }
        {
            line = $0
            sub(/^[ \t]+/, "", line)
            # Exact key match: the key must be followed by optional spaces and `=`
            if (index(line, k) == 1) {
                rest = substr(line, length(k) + 1)
                if (rest ~ /^[ \t]*=/) {
                    sub(/^[ \t]*=[ \t]*/, "", rest)
                    val = rest
                    found = 1
                }
            }
        }
        END { if (found) print val; exit(found ? 0 : 1) }
    ' "$file"
}

# Modify or set key's value in a `key = value` config file (appends key if missing).
# Only lines whose key is exactly `<key>` change: `port` never touches `export_port`.
# Usage: mbf::config::set <file> <key> <new_value>
function mbf::config::set() {
    local file="$1"
    local key="$2"
    local val="$3"
    [ -f "$file" ] || return 1
    mbf::is_dryrun && return 0

    MBF_K="$key" MBF_V="$val" awk '
        BEGIN { k = ENVIRON["MBF_K"]; v = ENVIRON["MBF_V"] }
        {
            line = $0
            sub(/^[ \t]+/, "", line)
            if (index(line, k) == 1 && substr(line, length(k) + 1) ~ /^[ \t]*=/) {
                # Keep everything before `=` (indentation + key) and replace the value
                print substr($0, 1, index($0, "=") - 1) "= " v
                found = 1
                next
            }
            print
        }
        END { if (!found) print k " = " v }
    ' "$file" | _mbf_replace_file "$file"
}

# Read a space-separated directive (sshd_config, nginx, php-fpm style: `Key value`).
# Key match is case-insensitive and the FIRST occurrence wins (sshd semantics).
# Returns 1 when the directive is absent.
# Usage: mbf::config::get_directive /etc/ssh/sshd_config PermitRootLogin
function mbf::config::get_directive() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return 1
    MBF_K="$key" awk '
        BEGIN { k = tolower(ENVIRON["MBF_K"]) }
        $1 ~ /^#/ { next }
        tolower($1) == k && NF >= 2 {
            v = $0
            sub(/^[ \t]*[^ \t]+[ \t]+/, "", v)
            sub(/[ \t;]+$/, "", v)
            print v
            found = 1
            exit
        }
        END { exit(found ? 0 : 1) }
    ' "$file"
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
    mbf::is_dryrun && return 0
    [ -f "$file" ] || touch "$file"
    if grep -Fqx -- "$line" "$file" 2>/dev/null; then
        return 0
    fi
    mbf::config::insert "$file" "$line"
}

# Idempotently manage a named multi-line block in a config file:
#   # BEGIN MBF:<block_id>
#   <content>
#   # END MBF:<block_id>
# An existing block is replaced IN PLACE (its position in the file is kept).
# A new block is appended, or prepended when the 4th argument is `top`.
# Usage: mbf::config::ensure_block <file> <block_id> <content> [top]
function mbf::config::ensure_block() {
    local file="$1"
    local block_id="$2"
    local content="$3"
    local position="${4:-bottom}"
    local start_mark="# BEGIN MBF:${block_id}"
    local end_mark="# END MBF:${block_id}"

    mbf::is_dryrun && return 0
    [ -f "$file" ] || touch "$file"

    if grep -Fqx -- "$start_mark" "$file" && ! grep -Fqx -- "$end_mark" "$file"; then
        mbf::log::error "mbf::config::ensure_block: '$start_mark' has no matching '$end_mark' in $file"
        return 1
    fi

    MBF_S="$start_mark" MBF_E="$end_mark" MBF_C="$content" MBF_POS="$position" awk '
        BEGIN {
            s = ENVIRON["MBF_S"]; e = ENVIRON["MBF_E"]; c = ENVIRON["MBF_C"]
            if (ENVIRON["MBF_POS"] == "top") { print s; print c; print e; done = 1 }
        }
        $0 == s { if (!done) { print s; print c; print e; done = 1 } skip = 1; next }
        skip && $0 == e { skip = 0; next }
        skip { next }
        { print }
        END { if (!done) { print s; print c; print e } }
    ' "$file" | _mbf_replace_file "$file"
}

# Delete every line containing the literal text <pattern>
# Usage: mbf::config::delete_line <file> <pattern>
function mbf::config::delete_line() {
    local file="$1"
    local match="$2"
    [ -f "$file" ] || return 1
    [ -n "$match" ] || return 1
    mbf::is_dryrun && return 0

    MBF_P="$match" awk 'index($0, ENVIRON["MBF_P"]) == 0' "$file" | _mbf_replace_file "$file"
}

# Replace every line containing the literal text <pattern> with <new_line>
# Usage: mbf::config::replace_line <file> <pattern> <new_line>
function mbf::config::replace_line() {
    local file="$1"
    local match="$2"
    shift 2
    [ -f "$file" ] || return 1
    [ -n "$match" ] || return 1
    mbf::is_dryrun && return 0

    MBF_P="$match" MBF_R="$*" awk '
        index($0, ENVIRON["MBF_P"]) > 0 { print ENVIRON["MBF_R"]; next }
        { print }
    ' "$file" | _mbf_replace_file "$file"
}

# Replace all occurrences of a literal substring in a file
# Usage: mbf::config::replace_text <file> <search> <replacement>
function mbf::config::replace_text() {
    local file="$1"
    local match="$2"
    shift 2
    [ -f "$file" ] || return 1
    [ -n "$match" ] || return 1
    mbf::is_dryrun && return 0

    MBF_P="$match" MBF_R="$*" awk '
        BEGIN { p = ENVIRON["MBF_P"]; r = ENVIRON["MBF_R"] }
        {
            out = ""
            line = $0
            while ((i = index(line, p)) > 0) {
                out = out substr(line, 1, i - 1) r
                line = substr(line, i + length(p))
            }
            print out line
        }
    ' "$file" | _mbf_replace_file "$file"
}

# Print line number of the first occurrence of fixed text in a file; returns 1 if not found
# Usage: mbf::config::line_number <file> <pattern>
function mbf::config::line_number() {
    local file="$1"
    shift
    [ -f "$file" ] || return 1

    local ln
    ln="$(grep -m1 -n -F -- "$*" "$file" 2>/dev/null | cut -d: -f1 || true)"
    if [ -n "$ln" ]; then
        printf '%s\n' "$ln"
        return 0
    fi
    return 1
}

# Insert a line immediately after the given line number (portable: no GNU `sed a`)
# Usage: mbf::config::append_after_line <file> <line_number> <text>
function mbf::config::append_after_line() {
    local file="$1"
    local ln="$2"
    shift 2
    [ -f "$file" ] || return 1
    mbf::is_dryrun && return 0

    MBF_N="$ln" MBF_T="$*" awk '
        { print }
        NR == ENVIRON["MBF_N"] + 0 { print ENVIRON["MBF_T"] }
    ' "$file" | _mbf_replace_file "$file"
}

# Create a `.mbf.bak` backup of a config file before editing (keeps mode/owner)
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
