# Library: `exec` — Safe Execution, Retries, Traps, Temp Files & Locks

`lib/exec.sh` provides safe, array-based command execution (no `eval`), automatic `--dry-run` simulation (`MBF_DRYRUN=1`), flaky command retries, LIFO `EXIT` cleanup hooks, auto-deleted temporary files/directories, stale-PID-aware concurrency locks, and idempotent step checkpointing.

---

## Environment Variables

- `MBF_DRYRUN=1` — When set, `mbf::exec::run`, `sudo`, and `as_user` log the command they would execute and return `0` without running it.
- `MBF_LOCK_DIR` — Directory for concurrency lock folders (default: `${TMPDIR:-/tmp}`).
- `MBF_STATE_FILE` — File storing completed step IDs for `mbf::exec::step_run` (default: `${TMPDIR:-/tmp}/mbf.steps.state`).

---

## Function Reference & Examples

### 1. `mbf::exec::run <cmd> [args...]`
Executes `<cmd>` as an argument array (preserving spaces and special characters without `eval`). Logs the command, skips execution when `MBF_DRYRUN=1`, and logs an error with the exit code if the command fails (safe under `mbf::strict`).

```bash
mbf::use exec

# Runs safely; skipped automatically when MBF_DRYRUN=1
mbf::exec::run systemctl reload nginx
mbf::exec::run docker compose -f /opt/app/docker-compose.yml up -d
```

### 2. `mbf::exec::sudo <cmd> [args...]`
Executes `<cmd>` via `sudo` when running as a non-root user, or directly via `mbf::exec::run` when already `root` (`EUID == 0`).

```bash
mbf::exec::sudo chown -R www-data:www-data /var/www/html
```

### 3. `mbf::exec::init_sudo`
Runs `sudo -v` interactively when non-root to cache `sudo` credentials before long-running tasks begin.

```bash
mbf::exec::init_sudo
```

### 4. `mbf::exec::as_user <username> <cmd> [args...]`
Executes `<cmd>` as `<username>` using `sudo -H -u <username> --`.

```bash
mbf::exec::as_user "www-data" php /var/www/magento2/bin/magento cache:flush
```

### 5. `mbf::exec::retry <attempts> <delay_sec> <cmd> [args...]`
Runs `<cmd>` up to `<attempts>` times, sleeping `<delay_sec>` seconds between failures. Returns `0` as soon as an attempt succeeds, or `1` after all attempts fail.

```bash
# Retry curl up to 5 times, waiting 3 seconds between failures
mbf::exec::retry 5 3 curl -fsSL https://api.example.com/health
```

### 6. `mbf::exec::scripts_in_dir <dir> <interpreter> [extension]`
Finds all `*.<extension>` files (default: `sh`) in `<dir>` and executes them in sorted lexical order (`01_pre.sh`, `02_migrate.sh`, etc.).

```bash
mbf::exec::scripts_in_dir "/etc/deploy/hooks.d" bash sh
```

### 7. `mbf::exec::on_exit "<cleanup_cmd>"`
Registers a cleanup command to run when the current shell or subshell exits. Multiple hooks are executed in **LIFO (Last-In, First-Out)** order, and any pre-existing `EXIT` trap is preserved.

```bash
mbf::exec::on_exit "docker compose -f /tmp/test-stack.yml down"
```

### 8. `mbf::exec::tmpfile <OUT_VAR>` & `mbf::exec::tmpdir <OUT_VAR>`
Creates a secure temporary file or directory in `${TMPDIR:-/tmp}`, assigns its path to `<OUT_VAR>`, and registers an `mbf::exec::on_exit` hook to delete it automatically when the script exits.

```bash
local report_file build_dir
mbf::exec::tmpfile report_file
mbf::exec::tmpdir  build_dir

printf 'Build report\n' > "$report_file"
tar -xzf release.tar.gz -C "$build_dir"
# Both $report_file and $build_dir are deleted automatically when the shell exits!
```

### 9. `mbf::exec::lock_acquire <lock_name> [timeout_sec]` & `mbf::exec::lock_release <lock_name>`
Acquires an atomic directory lock (`${MBF_LOCK_DIR}/mbf.<lock_name>.lock`) and records `$$` in `pid`.
- If an existing lock belongs to a dead process (`! kill -0 "$pid"`), `lock_acquire` automatically cleans up the stale lock and acquires it.
- Automatically releases the lock on shell exit, or immediately when `mbf::exec::lock_release` is called.

```bash
# Wait up to 10 seconds to acquire the 'nightly_deploy' lock
mbf::exec::lock_acquire "nightly_deploy" 10 || mbf::die "Another deployment is already running!"

mbf::exec::run /usr/local/bin/run-migrations.sh

mbf::exec::lock_release "nightly_deploy"
```

### 10. `mbf::exec::step_run <step_id> <cmd> [args...]`, `step_done`, & `step_mark`
Provides idempotent checkpointing across script re-runs using `MBF_STATE_FILE`:
- `mbf::exec::step_done "<step_id>"` — Returns `0` if `<step_id>` is already recorded in `MBF_STATE_FILE`.
- `mbf::exec::step_mark "<step_id>"` — Records `<step_id>` as completed in `MBF_STATE_FILE`.
- `mbf::exec::step_run "<step_id>" <cmd> [args...]` — Skips `<cmd>` if `step_done` is true; otherwise runs `<cmd>` and calls `step_mark` on success.

```bash
export MBF_STATE_FILE="/var/lib/mbf/provision.steps"

# If the script fails on step 02 and you re-run it, step 01 is skipped automatically:
mbf::exec::step_run "01_install_packages" mbf::system::pkg_install nginx redis-server
mbf::exec::step_run "02_seed_database"    /usr/local/bin/seed-db.sh

# Manual step check / mark:
if ! mbf::exec::step_done "03_custom_check"; then
    mbf::exec::step_mark "03_custom_check"
fi
```

### 8. `mbf::exec::timeout <seconds> <cmd> [args...]`
Runs `<cmd>` with a maximum wall-clock timeout (uses `timeout`/`gtimeout` when available, with a pure-Bash watchdog fallback). Returns `124` on timeout and respects `MBF_DRYRUN=1`.

```bash
mbf::exec::timeout 30 curl -fsSL https://example.com/health
```

### 9. `mbf::exec::confirm "<prompt>" [default:n|y]`
CI-aware interactive confirmation prompt. Auto-accepts when `MBF_YES=1`, falls back to `[default]` in non-interactive shells or when `CI=1`, and prompts `[y/N]` / `[Y/n]` interactively otherwise.

```bash
if mbf::exec::confirm "Proceed with production database migration?" "n"; then
    mbf::exec::run ./migrate.sh
fi
```

> **Note:** `mbf::exec::retry` also supports exponential backoff via `MBF_RETRY_BACKOFF=exp` (capped by `MBF_RETRY_MAX_DELAY`, default `60`s), and `mbf::exec::on_exit` automatically traps `INT` and `TERM` in addition to `EXIT`.
