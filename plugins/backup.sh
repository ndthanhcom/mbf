#!/usr/bin/env bash
# @mbf-module: backup
# @mbf-rank: ••
# mbf:requires log exec str
# ==============================================================================
# mbf plugin: backup
# Timestamped Directory Archiving (`.tar.gz` + `.sha256` manifest), Verification
# & Retention Policy Pruning
# ==============================================================================

# Create a timestamped `.tar.gz` archive of `<src_dir>` inside `<dest_dir>` + `.sha256` manifest
# Outputs the created archive path on stdout.
# Usage: mbf::backup::archive_dir <src_dir> <dest_dir> [prefix]
function mbf::backup::archive_dir() {
    local src_dir="$1"
    local dest_dir="$2"
    local prefix="${3:-$(basename "$src_dir")}"
    local ts
    ts="$(date +'%Y%m%d_%H%M%S')"
    local archive_path="${dest_dir}/${prefix}_${ts}.tar.gz"

    if [ ! -d "$src_dir" ]; then
        mbf::log::error "mbf::backup::archive_dir: source directory '$src_dir' not found"
        return 1
    fi

    if mbf::is_dryrun; then
        printf '%s\n' "$archive_path"
        return 0
    fi

    mkdir -p "$dest_dir" || return 1
    tar -czf "$archive_path" -C "$(dirname "$src_dir")" "$(basename "$src_dir")" || {
        rm -f "$archive_path"
        return 1
    }

    local hash
    if hash="$(mbf::str::sha256 "$archive_path")"; then
        printf '%s  %s\n' "$hash" "$(basename "$archive_path")" > "${archive_path}.sha256"
    fi
    printf '%s\n' "$archive_path"
}

# Verify an archive against its companion `<archive>.sha256` manifest file
# Usage: mbf::backup::verify <archive_path>
function mbf::backup::verify() {
    local archive_path="$1"
    local manifest="${archive_path}.sha256"

    if [ ! -f "$archive_path" ] || [ ! -f "$manifest" ]; then
        mbf::log::error "mbf::backup::verify: archive or manifest not found for '$archive_path'"
        return 1
    fi

    local expected
    expected="$(awk '{print $1; exit}' "$manifest")"
    mbf::str::verify_sha256 "$archive_path" "$expected"
}

# Prune backup `.tar.gz`, `.tar.gz.sha256`, and `.sql.gz` files older than `<keep_days>`
# Usage: mbf::backup::prune <backup_dir> [keep_days]
function mbf::backup::prune() {
    local backup_dir="$1"
    local keep_days="${2:-7}"

    [ -d "$backup_dir" ] || return 0
    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would prune backups older than ${keep_days} days in $backup_dir"
        return 0
    fi

    find "$backup_dir" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.tar.gz.sha256" -o -name "*.sql.gz" \) -mtime "+${keep_days}" -delete
}
