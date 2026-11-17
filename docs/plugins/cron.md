# Plugin: `cron` `[••]` — Tagged Idempotent Crontab Manager

`plugins/cron.sh` manages scheduled cron entries using unique end-of-line tags (`# mbf:id=<job_id>`) so your scripts can add, update, disable, enable, or remove specific cron jobs idempotently without disturbing unmanaged user cron entries. It also provides `mbf::cron::run_guarded` to wrap scheduled commands in non-overlapping concurrency locks with automatic failure alerts.

---

## Environment Variables

- `MBF_CRONTAB_FILE` — Optional file path override (used for testing or managing custom crontab files instead of the system `crontab` binary).

---

## Function Reference & Examples

### 1. `mbf::cron::set <job_id> "<schedule>" "<command>" [user]`
Adds or updates the cron entry tagged with `# mbf:id=<job_id>`. Because matching checks the exact end-of-line tag, updating or removing `backup` never affects `backup_db`.

```bash
mbf::use cron

# Add or update a job running every 5 minutes
mbf::cron::set "m2_cron" "*/5 * * * *" "/usr/bin/php /var/www/magento2/bin/magento cron:run"

# Add a nightly job for a specific system user
mbf::cron::set "nightly_db_backup" "0 2 * * *" "/usr/local/bin/backup.sh" "root"
```

Resulting crontab entry:
```text
*/5 * * * * /usr/bin/php /var/www/magento2/bin/magento cron:run # mbf:id=m2_cron
```

### 2. `mbf::cron::list [user]`
Prints all `mbf`-managed cron jobs (lines containing `# mbf:id=`).

```bash
mbf::cron::list
```

### 3. `mbf::cron::disable <job_id> [user]` & `mbf::cron::enable <job_id> [user]`
Temporarily comments out a managed cron job with `#MBF_DISABLED# ` (for example, during a deployment window) and re-enables it afterward.

```bash
# Pause cron jobs during deployment
mbf::cron::disable "m2_cron"

# ... run deployment steps ...

# Re-enable cron jobs
mbf::cron::enable "m2_cron"
```

### 4. `mbf::cron::remove <job_id> [user]`
Removes the cron job tagged with `# mbf:id=<job_id>` while leaving all other cron entries untouched.

```bash
mbf::cron::remove "old_report_job"
```

### 5. `mbf::cron::run_guarded <job_id> <cmd> [args...]`
Executes `<cmd> [args...]` inside a non-overlapping lock (`cron_<job_id>`):
- If a previous run of `<job_id>` is still active, logs an error and returns `1` immediately instead of stacking overlapping processes.
- Logs start time and total execution duration in seconds.
- If `<cmd>` exits non-zero (even under `mbf::strict`), releases the lock, logs the failure, and automatically triggers `mbf::notify::alert` if the `notify` plugin is loaded.

```bash
mbf::use cron notify
export MBF_SLACK_WEBHOOK="https://hooks.slack.com/services/T000/B000/XXXX"

# Run reindex guarded by a lock; alerts Slack automatically if it fails:
mbf::cron::run_guarded "m2_reindex" /usr/bin/php /var/www/magento2/bin/magento indexer:reindex
```
