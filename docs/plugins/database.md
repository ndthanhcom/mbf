# Plugin: `database` `[••]` — MySQL, PostgreSQL & Redis Provisioning and Dump/Restore

`plugins/database.sh` provisions MySQL/MariaDB, PostgreSQL, and Redis services, creates databases and least-privilege users idempotently, and performs atomic compressed SQL dumps and restores with `PIPESTATUS` verification.

---

## Function Reference & Examples

### 1. `mbf::database::ensure_mysql`, `ensure_postgres`, & `ensure_redis`
Installs the corresponding server package (`mariadb-server` / `mysql-server`, `postgresql`, or `redis-server`) if missing and ensures the system service is enabled and running.

```bash
mbf::use database

mbf::database::ensure_mysql
mbf::database::ensure_postgres
mbf::database::ensure_redis
```

### 2. `mbf::database::create_db_and_user <mysql|postgres> <db_name> <db_user> <db_pass>`
Idempotently creates `<db_name>` and `<db_user>` and grants privileges on `<db_name>` to `<db_user>`:
- Validates that `<db_name>` and `<db_user>` are alphanumeric identifiers (`mbf::system::is_alnum`).
- Escapes single quotes inside `<db_pass>` safely.
- Executes PostgreSQL creation in a single `psql -v ON_ERROR_STOP=1` session.

```bash
# MySQL / MariaDB
mbf::database::create_db_and_user "mysql" "magento2_prod" "m2_user" "$DB_PASSWORD"

# PostgreSQL
mbf::database::create_db_and_user "postgres" "analytics_db" "analytics_user" "$PG_PASSWORD"
```

### 3. `mbf::database::dump <mysql|postgres> <db_name> <out_file.sql.gz>`
Dumps `<db_name>` using `mysqldump --single-transaction` or `pg_dump` and compresses it via `gzip` into a temporary sibling file first:
- Checks `PIPESTATUS` on both the dump command and `gzip`.
- If either stage fails, deletes the temporary file and returns `1` so a failed dump never leaves an empty `.sql.gz` file on disk.

```bash
mbf::database::dump "mysql" "magento2_prod" "/var/backups/m2_prod_$(date +%F).sql.gz"
```

### 4. `mbf::database::restore <mysql|postgres> <db_name> <in_file>`
Restores `<db_name>` from either a compressed `.sql.gz` file or a plain `.sql` file, verifying `PIPESTATUS`.

```bash
# Restore from compressed .sql.gz
mbf::database::restore "mysql" "magento2_staging" "/var/backups/m2_prod_2026-11-16.sql.gz"

# Restore from plain .sql
mbf::database::restore "postgres" "analytics_db" "/tmp/schema.sql"
```
