# Plugin: `backup` `[••]` — Directory Archiving, Checksum Verification & Retention Pruning

`plugins/backup.sh` creates timestamped `.tar.gz` directory archives paired with `.sha256` checksum manifests, verifies archive integrity prior to restore, and prunes expired backups according to a retention policy.

---

## Function Reference & Examples

### 1. `mbf::backup::archive_dir <src_dir> <dest_dir> [prefix]`
Creates `<dest_dir>/<prefix>_YYYYMMDD_HHMMSS.tar.gz` and `<archive>.sha256`, and prints the created archive path to `stdout`.

```bash
mbf::use backup

archive_path="$(mbf::backup::archive_dir "/var/www/magento2/pub/media" "/var/backups/media" "m2_media")"
echo "Created archive: ${archive_path}"
echo "Checksum file  : ${archive_path}.sha256"
```

### 2. `mbf::backup::verify <archive_path>`
Verifies that `<archive_path>` matches the SHA-256 hash recorded in `<archive_path>.sha256`. Returns `0` if valid, or logs an error and returns `1` if missing or corrupted.

```bash
if mbf::backup::verify "$archive_path"; then
    mbf::log::ok "Archive integrity verified: ${archive_path}"
fi
```

### 3. `mbf::backup::prune <backup_dir> [keep_days]`
Deletes `.tar.gz`, `.tar.gz.sha256`, and `.sql.gz` files in `<backup_dir>` whose modification time is older than `[keep_days]` (default: `7`). Respects `MBF_DRYRUN=1`.

```bash
# Keep only the last 14 days of backups
mbf::backup::prune "/var/backups/media" 14
```

---

## Complete Nightly Backup Script Example

```bash
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::strict
mbf::use log database backup notify

function main() {
    local backup_root="/var/backups/nightly"

    # 1. Dump MySQL database
    mbf::database::dump "mysql" "magento2_prod" "${backup_root}/m2_db_$(date +%F).sql.gz"

    # 2. Archive media directory and verify its SHA-256 manifest
    local media_tar
    media_tar="$(mbf::backup::archive_dir "/var/www/magento2/pub/media" "$backup_root" "m2_media")"
    mbf::backup::verify "$media_tar"

    # 3. Prune backups older than 7 days
    mbf::backup::prune "$backup_root" 7

    mbf::log::ok "Nightly backup and rotation complete."
}

main "$@"
```
