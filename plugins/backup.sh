#!/usr/bin/env bash
# mbf:requires log exec crypto
# ==============================================================================
# mbf plugin: backup
# Directory Archiving (with SHA-256 manifest), Remote Transfer, and Retention Pruner
# ==============================================================================

# Create a timestamped `.tar.gz` archive of `<src_dir>` inside `<dest_dir>` + `.sha256` file
# Outputs the created archive path on stdout
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
    tar -czf "$archive_path" -C "$(dirname "$src_dir")" "$(basename "$src_dir")" || return 1

    local hash
    if hash="$(mbf::crypto::sha256 "$archive_path")"; then
        printf '%s  %s\n' "$hash" "$(basename "$archive_path")" > "${archive_path}.sha256"
    fi
    printf '%s\n' "$archive_path"
}

# Transfer a backup file/dir to a remote host via rsync
# Usage: mbf::backup::upload_rsync <local_path> <user@host:/remote/path>
function mbf::backup::upload_rsync() {
    local local_path="$1"
    local remote_target="$2"
    mbf::exec::run rsync -az "$local_path" "$remote_target"
}

# Upload a backup file to an S3 bucket via aws-cli
# Usage: mbf::backup::upload_s3 <local_file> <s3://bucket/path/>
function mbf::backup::upload_s3() {
    local local_file="$1"
    local s3_uri="$2"
    mbf::exec::run aws s3 cp "$local_file" "$s3_uri"
}

# Prune backup `.tar.gz` and `.sql.gz` files older than `<keep_days>` in `<backup_dir>`
# Usage: mbf::backup::prune <backup_dir> <keep_days>
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
