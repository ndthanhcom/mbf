#!/usr/bin/env bash
# @mbf-module: database
# @mbf-rank: ••
# mbf:requires log exec system
# ==============================================================================
# mbf plugin: database
# MySQL/MariaDB, PostgreSQL & Redis Provisioning, Least-Privilege User Creation,
# and Atomic Compressed Dump/Restore
# (For directory archiving and backup rotation, see `plugins/backup.sh`.)
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
# Validates identifiers (`db_name`, `db_user`) and escapes single quotes in passwords.
# Usage: mbf::database::create_db_and_user <mysql|postgres> <db_name> <db_user> <db_pass>
function mbf::database::create_db_and_user() {
    local engine="$1"
    local db_name="$2"
    local db_user="$3"
    local db_pass="$4"

    if ! mbf::system::is_alnum "$db_name" || ! mbf::system::is_alnum "$db_user"; then
        mbf::log::error "mbf::database::create_db_and_user: db_name and db_user must be alphanumeric"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would create $engine database '$db_name' and user '$db_user'"
        return 0
    fi

    local esc_pass="${db_pass//\'/\'\'}"
    case "$engine" in
        mysql|mariadb)
            # Pipe SQL via stdin so credentials never appear in `ps` / `/proc/<pid>/cmdline`
            local sql="CREATE DATABASE IF NOT EXISTS \`${db_name}\`; CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${esc_pass}'; GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost'; FLUSH PRIVILEGES;"
            printf '%s\n' "$sql" | mbf::system::as_root mysql
            ;;
        postgres|postgresql)
            # Single idempotent psql session piped over stdin (no password in argv, safe under stdout logging)
            local pg_sql="SELECT 'CREATE DATABASE ${db_name}' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db_name}')\\gexec
DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${db_user}') THEN CREATE ROLE ${db_user} LOGIN PASSWORD '${esc_pass}'; ELSE ALTER ROLE ${db_user} WITH LOGIN PASSWORD '${esc_pass}'; END IF; END \$\$;
GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};"
            printf '%s\n' "$pg_sql" | mbf::exec::as_user postgres psql -v ON_ERROR_STOP=1
            ;;
        *)
            mbf::log::error "Unsupported database engine: $engine"
            return 1
            ;;
    esac
}

# Dump database to a `.sql.gz` file atomically.
# Checks `PIPESTATUS` so a failed `mysqldump`/`pg_dump` never leaves an empty `.gz` file.
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
    local tmp_out="${out_file}.mbf.part.$$"
    local -a pipe_rc=()

    case "$engine" in
        mysql|mariadb)
            mysqldump --single-transaction "$db_name" | gzip -c > "$tmp_out" || true
            pipe_rc=("${PIPESTATUS[@]}")
            ;;
        postgres|postgresql)
            sudo -u postgres pg_dump "$db_name" | gzip -c > "$tmp_out" || true
            pipe_rc=("${PIPESTATUS[@]}")
            ;;
        *)
            mbf::log::error "Unsupported database engine: $engine"
            return 1
            ;;
    esac

    if [ "${pipe_rc[0]:-1}" -ne 0 ] || [ "${pipe_rc[1]:-1}" -ne 0 ]; then
        rm -f "$tmp_out"
        mbf::log::error "Database dump failed for $engine '$db_name'"
        return 1
    fi

    mv -f "$tmp_out" "$out_file"
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

    local -a pipe_rc=(0 0)
    case "$engine" in
        mysql|mariadb)
            if [[ "$in_file" == *.gz ]]; then
                gzip -dc "$in_file" | mysql "$db_name" || true
                pipe_rc=("${PIPESTATUS[@]}")
            else
                mysql "$db_name" < "$in_file" || pipe_rc=($? 0)
            fi
            ;;
        postgres|postgresql)
            if [[ "$in_file" == *.gz ]]; then
                gzip -dc "$in_file" | sudo -u postgres psql -v ON_ERROR_STOP=1 "$db_name" || true
                pipe_rc=("${PIPESTATUS[@]}")
            else
                sudo -u postgres psql -v ON_ERROR_STOP=1 "$db_name" < "$in_file" || pipe_rc=($? 0)
            fi
            ;;
        *)
            mbf::log::error "Unsupported database engine: $engine"
            return 1
            ;;
    esac

    if [ "${pipe_rc[0]:-1}" -ne 0 ] || [ "${pipe_rc[1]:-0}" -ne 0 ]; then
        mbf::log::error "Database restore failed for $engine '$db_name' from $in_file"
        return 1
    fi
    return 0
}
