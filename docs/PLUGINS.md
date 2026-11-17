# MBF Plugins Reference (`plugins/`)

Plugins provide higher-level operational capabilities for AI CLI integration, server auditing, multi-channel notifications, security hardening, web stack provisioning, database lifecycle, directory backups, cron management, and polyglot runtimes. Load any plugin with `mbf::use <plugin>`.

Each section below summarizes the plugin's functions, provides a quick example, and links to its **detailed function-by-function guide** in [`docs/plugins/`](plugins/).

---

## 1. `ai` `[•••]` — Mainstream AI CLI Integration
**Detailed Guide & Function Examples**: [`docs/plugins/ai.md`](plugins/ai.md)

Queries mainstream AI CLI tools (`claude`, `agy`, `gemini`, `codex`) or secondary/HTTP API fallbacks non-interactively to diagnose server logs, audit configurations, or generate shell commands.

### Functions
- `mbf::ai::detect` — Print the highest-priority available AI provider.
- `mbf::ai::ensure [provider]` — Verify an AI CLI is installed; print installation instructions if missing.
- `mbf::ai::ask "<prompt>" [context_file_or_dash]` — Run a one-shot prompt with optional file or piped `stdin` (`-`).
- `mbf::ai::analyze <file_or_dash_or_text> [instruction]` — Send a log file, piped `stdin` (`-`), or text to the AI CLI for root-cause analysis.
- `mbf::ai::cmd "<task_description>"` — Request a raw executable bash command (markdown fences stripped).

```bash
mbf::use ai
mbf::ai::analyze "/var/log/nginx/error.log" "Diagnose 502 Bad Gateway errors and recommend fixes."
```

---

## 2. `monitor` `[•••]` — Server Resource, Performance & Security Review
**Detailed Guide & Function Examples**: [`docs/plugins/monitor.md`](plugins/monitor.md)

Provides human-readable server audits and structured JSON metrics snapshots for SaaS ingestion.

### Functions
- `mbf::monitor::resources` — CPU specs, memory capacity, and disk usage.
- `mbf::monitor::performance` — Load averages, top 5 CPU/RAM processes, and TCP connection summary.
- `mbf::monitor::logs [log_file] [max_lines]` — Scan syslog/auth logs or `journalctl` for OOM/fatal errors and SSH brute-force attempts.
- `mbf::monitor::firewall` — Active firewall rules (`ufw`, `firewalld`, `iptables`) and listening ports.
- `mbf::monitor::cron [custom_dir]` — Inspect user and system crontabs.
- `mbf::monitor::history [history_file] [max_lines]` — Review recent and privileged commands.
- `mbf::monitor::report [log_file] [history_file]` — Run all 6 checks in a single report.
- `mbf::monitor::collect_review_json [sshd_config]` — Output host, kernel, CPU, load, and SSH audit state as a JSON object.

```bash
mbf::use monitor
mbf::monitor::report
metrics="$(mbf::monitor::collect_review_json)"
```

---

## 3. `notify` `[•••]` — Multi-Channel Messaging, Alerts & Signed Webhooks
**Detailed Guide & Function Examples**: [`docs/plugins/notify.md`](plugins/notify.md)

Sends operational notifications via Email, Slack, Telegram, and HMAC-SHA256 signed SaaS webhooks.

### Functions
- `mbf::notify::email <to> <subject> <body>` — Send email via `mail`, `mailx`, `sendmail`, `msmtp`, or `MBF_MAIL_CMD`.
- `mbf::notify::slack <message> [webhook_url]` — POST message to Slack webhook.
- `mbf::notify::telegram <message> [bot_token] [chat_id]` — Send message via Telegram Bot API.
- `mbf::notify::webhook <job_id> <step> <status> <message> [webhook_url]` — POST an HMAC-SHA256 signed JSON event to `MBF_SAAS_WEBHOOK_URL`.
- `mbf::notify::alert <title> <message>` — Broadcast alert to all configured channels (`MBF_SLACK_WEBHOOK`, `MBF_TELEGRAM_*`, `MBF_MAIL_TO`).

```bash
mbf::use notify
export MBF_SLACK_WEBHOOK="https://hooks.slack.com/services/T00/B00/X00"
mbf::notify::alert "Deploy Complete" "Release 2026.11 is live on prod-web01"
```

---

## 4. `security` `[•••]` — SSH Hardening, System Audit & Firewall Management
**Detailed Guide & Function Examples**: [`docs/plugins/security.md`](plugins/security.md)

Audits and hardens SSH/system configurations (including `sshd_config.d/*.conf` drop-ins) and manages `ufw`, `firewalld`, or `iptables` ports safely.

### Functions
- `mbf::security::audit_ssh [sshd_config]` — Check effective SSH port, `PermitRootLogin`, `PasswordAuthentication`, and `PermitEmptyPasswords`.
- `mbf::security::audit_system [passwd_file]` — List UID 0 accounts and check `fail2ban` status.
- `mbf::security::harden_ssh [sshd_config] [disable_password_auth:0|1]` — Backup config, disable root login and empty/password auth, validate with `sshd -t`, and reload SSH.
- `mbf::security::install_fail2ban` — Install and enable `fail2ban`.
- `mbf::security::fw_backend` — Detect `ufw`, `firewalld`, or `iptables`.
- `mbf::security::fw_allow <port> [tcp|udp]` / `mbf::security::fw_deny <port> [tcp|udp]` — Idempotently allow or deny port traffic.
- `mbf::security::fw_enable_baseline [ssh_port]` — Allow SSH, HTTP (`80`), and HTTPS (`443`), then enable firewall default-deny incoming policy.

```bash
mbf::use security
mbf::security::harden_ssh "/etc/ssh/sshd_config" 1
mbf::security::fw_enable_baseline 22
```

---

## 5. `webserver` `[••]` — Nginx Vhosts, SSL Lifecycle & Application Stacks
**Detailed Guide & Function Examples**: [`docs/plugins/webserver.md`](plugins/webserver.md)

Provisions Nginx virtual hosts from `.tpl` templates with automatic rollback on `nginx -t` failure, manages Let's Encrypt or self-signed SSL certificates, and deploys PHP-FPM or Git applications.

### Functions
- **Nginx Virtual Hosts**: `mbf::webserver::ensure_nginx`, `mbf::webserver::vhost_static <domain> <root_dir>`, `mbf::webserver::vhost_php <domain> <root_dir> [php_version]`, `mbf::webserver::vhost_proxy <domain> <upstream_port>`, `mbf::webserver::vhost_remove <domain>`
- **SSL Certificates**: `mbf::webserver::ssl_letsencrypt <domain> <email> [webroot_dir]`, `mbf::webserver::ssl_self_signed <domain> <dest_dir> [days]`, `mbf::webserver::ssl_expiry_days <pem_file_or_domain>`, `mbf::webserver::ssl_check_renewals [certs_dir] [warn_days]`
- **Application Runtimes & Deployment**: `mbf::webserver::ensure_php [php_version] [extra_exts...]`, `mbf::webserver::deploy_git <app_dir> <repo_url> [branch] [build_cmd]`

```bash
mbf::use webserver
mbf::webserver::ensure_nginx
mbf::webserver::vhost_php "shop.example.com" "/var/www/shop/pub" "8.2"
mbf::webserver::ssl_letsencrypt "shop.example.com" "ops@example.com"
```

---

## 6. `database` `[••]` — MySQL, PostgreSQL & Redis Provisioning and Dump/Restore
**Detailed Guide & Function Examples**: [`docs/plugins/database.md`](plugins/database.md)

Provisions database engines, creates databases and least-privilege users idempotently, and dumps/restores compressed SQL archives atomically.

### Functions
- `mbf::database::ensure_mysql` / `mbf::database::ensure_postgres` / `mbf::database::ensure_redis`
- `mbf::database::create_db_and_user <mysql|postgres> <db_name> <db_user> <db_pass>`
- `mbf::database::dump <mysql|postgres> <db_name> <out_file.sql.gz>`
- `mbf::database::restore <mysql|postgres> <db_name> <in_file>`

```bash
mbf::use database
mbf::database::create_db_and_user "mysql" "app_prod" "app_user" "$DB_PASS"
mbf::database::dump "mysql" "app_prod" "/var/backups/app_prod.sql.gz"
```

---

## 7. `backup` `[••]` — Directory Archiving, Checksum Verification & Retention Pruning
**Detailed Guide & Function Examples**: [`docs/plugins/backup.md`](plugins/backup.md)

Creates timestamped `.tar.gz` archives with companion `.sha256` manifests, verifies archive integrity, and prunes expired backups.

### Functions
- `mbf::backup::archive_dir <src_dir> <dest_dir> [prefix]` — Create timestamped `.tar.gz` + `.sha256` manifest and print archive path.
- `mbf::backup::verify <archive_path>` — Verify archive against `<archive_path>.sha256`.
- `mbf::backup::prune <backup_dir> [keep_days]` — Delete `.tar.gz`, `.tar.gz.sha256`, and `.sql.gz` archives older than `<keep_days>`.

```bash
mbf::use backup
archive="$(mbf::backup::archive_dir "/var/www/app/uploads" "/var/backups" "uploads")"
mbf::backup::verify "$archive"
mbf::backup::prune "/var/backups" 7
```

---

## 8. `cron` `[••]` — Tagged Idempotent Crontab Manager
**Detailed Guide & Function Examples**: [`docs/plugins/cron.md`](plugins/cron.md)

Manages cron jobs by unique `# mbf:id=<job_id>` end-of-line tags without disturbing unmanaged user cron entries, and wraps scheduled jobs in non-overlapping locks.

### Functions
- `mbf::cron::set <job_id> "<schedule>" "<command>" [user]`
- `mbf::cron::remove <job_id> [user]`
- `mbf::cron::disable <job_id> [user]` / `mbf::cron::enable <job_id> [user]`
- `mbf::cron::list [user]`
- `mbf::cron::run_guarded <job_id> <cmd> [args...]` — Execute `<cmd>` inside `mbf::exec::lock_acquire`, log execution duration, and trigger `mbf::notify::alert` on failure.

```bash
mbf::use cron
mbf::cron::set "nightly_backup" "0 3 * * *" "/usr/local/bin/backup.sh"
```

---

## 9. `runtime` `[•]` — Polyglot Node.js, Python & Binary Integration
**Detailed Guide & Function Examples**: [`docs/plugins/runtime.md`](plugins/runtime.md)

Integrates external system tools, Node.js scripts, and Python scripts into `mbf` workflows, and automatically packages referenced `.js`/`.py` files and `INSTALL.md` when exported via `mbf export`.

### Functions
- `mbf::runtime::install_hint <pkg_name> [download_url]` / `mbf::runtime::ensure_pkg <pkg_name> [cmd_name] [download_url]`
- `mbf::runtime::download <url> <dest_path> [expected_sha256]`
- `mbf::runtime::check_node [min_major]` / `mbf::runtime::npm_install [dir]` / `mbf::runtime::run_node <script.js> [args...]`
- `mbf::runtime::check_python [min_major]` / `mbf::runtime::pip_install [requirements.txt] [venv]` / `mbf::runtime::run_python <script.py> [args...]`

```bash
mbf::use runtime
mbf::runtime::check_python 3
mbf::runtime::run_python "scripts/analyze_metrics.py" "--days=7"
```

---

## 10. `obfuscator` `[•]` — Bash Script Obfuscation Add-on
**Detailed Guide & Function Examples**: [`docs/plugins/obfuscator.md`](plugins/obfuscator.md)

Wraps `bash-obfuscate` to obfuscate exported standalone scripts prior to distribution or binary compilation (`mbf compile --obfuscate`).

### Functions
- `mbf::obfuscator::run <input.sh> [output.sh]`

```bash
mbf::use obfuscator
mbf::obfuscator::run "dist/deploy.sh" "dist/deploy.obf.sh"
```
