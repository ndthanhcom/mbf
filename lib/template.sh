#!/usr/bin/env bash
# mbf:requires log fs
# ==============================================================================
# mbf core library: template
# Config template rendering ({{VAR}}), atomic file writes, and backup/rollback
# ==============================================================================

# Render a template file by replacing {{VAR}} placeholders with environment/passed variables
# Usage: mbf::template::render <tpl_file> <dest_file> [KEY1=val1 KEY2=val2 ...]
function mbf::template::render() {
    local tpl_file="$1"
    local dest_file="$2"
    shift 2 2>/dev/null || true

    if [ ! -f "$tpl_file" ]; then
        mbf::log::error "mbf::template::render: template file not found: $tpl_file"
        return 1
    fi

    local content pair k v
    content="$(cat "$tpl_file")"

    # 1. Apply explicit KEY=val arguments first
    for pair in "$@"; do
        if [[ "$pair" == *"="* ]]; then
            k="${pair%%=*}"
            v="${pair#*=}"
            content="${content//\{\{${k}\}\}/$v}"
        fi
    done

    # 2. Replace any remaining {{VAR}} placeholders from current shell variables
    while [[ "$content" =~ \{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\} ]]; do
        k="${BASH_REMATCH[1]}"
        v="${!k:-}"
        content="${content//\{\{${k}\}\}/$v}"
    done

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would render template $tpl_file -> $dest_file"
        return 0
    fi

    printf '%s\n' "$content" | mbf::template::write_atomic "$dest_file"
}

# Atomically write stdin content to `<dest_file>` via a sibling temp file + mv
# Usage: printf '...' | mbf::template::write_atomic /etc/nginx/conf.d/site.conf
function mbf::template::write_atomic() {
    local dest_file="$1"
    local dest_dir
    dest_dir="$(dirname "$dest_file")"
    mkdir -p "$dest_dir" 2>/dev/null || return 1

    local tmp_out="${dest_file}.mbf.tmp.$$"
    cat > "$tmp_out" || { rm -f "$tmp_out"; return 1; }
    mv -f "$tmp_out" "$dest_file"
}

# Create a `.mbf.bak` backup of a file before editing
# Usage: mbf::template::backup /etc/ssh/sshd_config
function mbf::template::backup() {
    local file="$1"
    [ -f "$file" ] || return 1
    mbf::is_dryrun && return 0
    cp -p "$file" "${file}.mbf.bak"
}

# Restore a file from its `.mbf.bak` backup
# Usage: mbf::template::rollback /etc/ssh/sshd_config
function mbf::template::rollback() {
    local file="$1"
    if [ ! -f "${file}.mbf.bak" ]; then
        mbf::log::error "mbf::template::rollback: no backup found for $file"
        return 1
    fi
    mbf::is_dryrun && return 0
    mv -f "${file}.mbf.bak" "$file"
    mbf::log::warn "Rolled back $file from backup"
}
