#!/usr/bin/env bash
# @mbf-module: database
# @mbf-rank: ••
# mbf:requires log exec system str
# ==============================================================================
# mbf plugin: database
# MySQL/MariaDB, PostgreSQL & Redis Provisioning, Dump/Restore & Backup Rotation
# ==============================================================================

function mbf::database::ensure_mysql() {
    if ! command -v mysql >/dev/null 2>&1; then
        mbf::system::pkg_install mariadb-server || mbf::system::pkg_install mysql-server || return 1
    fi
    mbf::system::service_ensure mariadb 2>/dev/null || mbf::system::service_ensure mysql
}

function mbf::database::ensure_postgres() {
    if ! command -v psql >/dev/null 2>&1; then
        mbf::system::pkg_install postgresql postgresql-contrib || return 1
    fi
    mbf::system::service_ensure postgresql
}

function mbf::database::ensure_redis() {
    if ! command -v redis-server >/dev/null 2>&1; then
        mbf::system::pkg_install redis-server || mbf::system::pkg_install redis || return 1
    fi
    mbf::system::service_ensure redis-server 2>/dev/null || mbf::system::service_ensure redis
}

# Create database and least-privilege user idempotently (supports mysql and postgres)
# Usage: mbf::database::create_db_and_user <mysql|postgres> <db_name> <db_user> <db_pass>
function mbf::database::create_db_and_user() {
    local engine="$1"
    local db_name="$2"
    local db_user="$3"
    local db_pass="$4"

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would create $engine database '$db_name' and user '$db_user'"
        return 0
    fi

    case "$engine" in
        mysql|mariadb)
            local sql="CREATE DATABASE IF NOT EXISTS \`${db_name}\`; CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}'; GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost'; FLUSH PRIVILEGES;"
            mbf::system::as_root mysql -e "$sql"
            ;;
        postgres|postgresql)
            mbf::exec::as_user postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = '${db_name}'" | grep -q 1 || \
                mbf::exec::as_user postgres psql -c "CREATE DATABASE ${db_name};"
            mbf::exec::as_user postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname = '${db_user}'" | grep -q 1 || \
                mbf::exec::as_user postgres psql -c "CREATE USER ${db_user} WITH ENCRYPTED PASSWORD '${db_pass}';"
            mbf::exec::as_user postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};"
            ;;
        *)
            mbf::log::error "Unsupported database engine: $engine"
            return 1
            ;;
    esac
}

# Dump database to a `.sql.gz` file
# Usage: mbf::database::dump <mysql|postgres> <db_name> <out_file.sql.gz>
function mbf::database::dump() {
    local engine="$1"
    local db_name="$2"
    local out_file="$3"

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would dump $engine database '$db_name' -> $out_file"
        return 0
    fi

    mkdir -p "$(dirname "$out_file")"
    case "$engine" in
        mysql|mariadb)
            mysqldump --single-transaction "$db_name" | gzip -c > "$out_file"
            ;;
        postgres|postgresql)
            sudo -u postgres pg_dump "$db_name" | gzip -c > "$out_file"
            ;;
        *)
            mbf::log::error "Unsupported database engine: $engine"
            return 1
            ;;
    esac
}

# Restore database from a `.sql.gz` or `.sql` dump file
# Usage: mbf::database::restore <mysql|postgres> <db_name> <in_file>
function mbf::database::restore() {
    local engine="$1"
    local db_name="$2"
    local in_file="$3"

    [ -f "$in_file" ] || { mbf::log::error "Dump file not found: $in_file"; return 1; }
    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would restore $engine database '$db_name' from $in_file"
        return 0
    fi

    case "$engine" in
        mysql|mariadb)
            if [[ "$in_file" == *.gz ]]; then
                gzip -dc "$in_file" | mysql "$db_name"
            else
                mysql "$db_name" < "$in_file"
            fi
            ;;
        postgres|postgresql)
            if [[ "$in_file" == *.gz ]]; then
                gzip -dc "$in_file" | sudo -u postgres psql "$db_name"
            else
                sudo -u postgres psql "$db_name" < "$in_file"
            fi
            ;;
        *)
            mbf::log::error "Unsupported database engine: $engine"
            return 1
            ;;
    esac
}

# Create a timestamped `.tar.gz` archive of `<src_dir>` inside `<dest_dir>` + `.sha256` manifest
# Outputs the created archive path on stdout
# Usage: mbf::database::archive_dir <src_dir> <dest_dir> [prefix]
function mbf::database::archive_dir() {
    local src_dir="$1"
    local dest_dir="$2"
    local prefix="${3:-$(basename "$src_dir")}"
    local ts
    ts="$(date +'%Y%m%d_%H%M%S')"
    local archive_path="${dest_dir}/${prefix}_${ts}.tar.gz"

    if [ ! -d "$src_dir" ]; then
        mbf::log::error "mbf::database::archive_dir: source directory '$src_dir' not found"
        return 1
    fi

    if mbf::is_dryrun; then
        printf '%s\n' "$archive_path"
        return 0
    fi

    mkdir -p "$dest_dir" || return 1
    tar -czf "$archive_path" -C "$(dirname "$src_dir")" "$(basename "$src_dir")" || return 1

    local hash
    if hash="$(mbf::str::sha256 "$archive_path")"; then
        printf '%s  %s\n' "$hash" "$(basename "$archive_path")" > "${archive_path}.sha256"
    fi
    printf '%s\n' "$archive_path"
}

# Prune backup `.tar.gz` and `.sql.gz` files older than `<keep_days>` in `<backup_dir>`
# Usage: mbf::database::prune_backups <backup_dir> <keep_days>
function mbf::database::prune_backups() {
    local backup_dir="$1"
    local keep_days="${2:-7}"

    [ -d "$backup_dir" ] || return 0
    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would prune backups older than ${keep_days} days in $backup_dir"
        return 0
    fi

    find "$backup_dir" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.tar.gz.sha256" -o -name "*.sql.gz" \) -mtime "+${keep_days}" -delete
}
