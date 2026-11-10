#!/usr/bin/env bash
# mbf:requires log exec os service
# ==============================================================================
# mbf plugin: database
# MySQL/MariaDB, PostgreSQL & Redis Provisioning, User Setup, Dump & Restore
# ==============================================================================

function mbf::database::ensure_mysql() {
    if ! command -v mysql >/dev/null 2>&1; then
        mbf::os::pkg_install mariadb-server || mbf::os::pkg_install mysql-server || return 1
    fi
    mbf::service::ensure_running mariadb 2>/dev/null || mbf::service::ensure_running mysql
}

function mbf::database::ensure_postgres() {
    if ! command -v psql >/dev/null 2>&1; then
        mbf::os::pkg_install postgresql postgresql-contrib || return 1
    fi
    mbf::service::ensure_running postgresql
}

function mbf::database::ensure_redis() {
    if ! command -v redis-server >/dev/null 2>&1; then
        mbf::os::pkg_install redis-server || mbf::os::pkg_install redis || return 1
    fi
    mbf::service::ensure_running redis-server 2>/dev/null || mbf::service::ensure_running redis
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
            mbf::exec::sudo mysql -e "$sql"
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
