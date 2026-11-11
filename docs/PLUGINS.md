# MBF Plugins Reference (`plugins/`)

Plugins provide higher-level operational capabilities for AI CLI integration, server auditing, security hardening, web stack provisioning, database lifecycle, cron management, and polyglot runtimes. Load any plugin with `mbf::use <plugin>`.

---

## 1. `ai` `[•••]` — Mainstream AI CLI Integration
Empowers `mbf` scripts to query AI CLI tools non-interactively to diagnose server logs, audit configurations, summarize build failures, or generate shell commands.

### Provider Priority
1. **Mainstream Coding & Ops CLIs (Primary)**:
   - `claude` (Claude Code CLI: `claude -p "<prompt>"`)
   - `agy` (Google Antigravity CLI: `agy -p "<prompt>"`)
   - `gemini` (Gemini CLI: `gemini -p "<prompt>"`)
   - `codex` (OpenAI Codex CLI: `codex exec "<prompt>"`)
2. **Secondary Fallbacks**:
   - `hermes` (`hermes chat -q`), `ollama` (`ollama run`), `llm`, or direct HTTP API fallback when `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, or `OPENAI_API_KEY` is exported.

### Environment Variables
- `MBF_AI_PROVIDER` — Force a specific provider (`claude`, `agy`, `gemini`, `codex`, `hermes`, `ollama`, `llm`, `api`).
- `MBF_AI_MODEL` — Override the model name.

### Functions
- `mbf::ai::detect` — Print the highest-priority available AI provider.
- `mbf::ai::ensure [provider]` — Verify an AI CLI is installed; print installation instructions if missing.
- `mbf::ai::ask "<prompt>" [context_file]` — Run a one-shot prompt, optionally attaching `<context_file>`.
- `mbf::ai::analyze <file_or_text> [instruction]` — Send a log file, config file, or audit output to the AI CLI for root-cause analysis and remediation steps.
- `mbf::ai::cmd "<task_description>"` — Request a raw executable bash command for `<task_description>` (markdown fences stripped).

---

## 2. `monitor` `[•••]` — Server Auditing, SaaS Telemetry & Multi-Channel Alerting
Provides human-readable server audits, structured JSON telemetry for SaaS backends, and multi-channel notifications (Email, Slack, Telegram).

### Functions
- **Server Inspection**:
  - `mbf::monitor::resources` — CPU specs, memory capacity, and disk usage.
  - `mbf::monitor::performance` — Load averages, top 5 CPU/RAM processes, and TCP connection summary.
  - `mbf::monitor::logs [log_file] [max_lines]` — Scan syslog/auth logs or `journalctl` for OOM/fatal errors and SSH brute-force attempts.
  - `mbf::monitor::firewall` — Active firewall rules (`ufw`, `firewalld`, `iptables`) and listening ports.
  - `mbf::monitor::cron [custom_dir]` — Inspect user and system crontabs.
  - `mbf::monitor::history [history_file] [max_lines]` — Review recent and privileged commands.
  - `mbf::monitor::report [log_file] [history_file]` — Run all 6 checks in a single report.
- **SaaS Agent Telemetry**:
  - `mbf::monitor::collect_review_json [sshd_config]` — Output host, kernel, CPU, load, and SSH audit state as a JSON object.
  - `mbf::monitor::send_event <job_id> <step> <status> <message> [webhook_url]` — POST an HMAC-SHA256 signed JSON event to `MBF_SAAS_WEBHOOK_URL` (signed with `MBF_SAAS_SECRET`).
- **Alerting**:
  - `mbf::monitor::notify_email <to> <subject> <body>`
  - `mbf::monitor::notify_slack <message> [webhook_url]`
  - `mbf::monitor::notify_telegram <message> [bot_token] [chat_id]`
  - `mbf::monitor::alert <title> <message>` — Broadcast to all configured channels (`MBF_SLACK_WEBHOOK`, `MBF_TELEGRAM_*`, `MBF_MAIL_TO`).

---

## 3. `security` `[•••]` — SSH Hardening, System Audit & Firewall Management
Audits and hardens SSH/system configurations and manages `ufw`, `firewalld`, or `iptables` ports safely.

### Functions
- `mbf::security::audit_ssh [sshd_config]` — Check SSH port, `PermitRootLogin`, `PasswordAuthentication`, and `PermitEmptyPasswords`.
- `mbf::security::audit_system [passwd_file]` — List UID 0 accounts and check `fail2ban` status.
- `mbf::security::harden_ssh [sshd_config] [disable_password_auth:0|1]` — Backup config, disable root login and empty/password auth, validate with `sshd -t`, and reload SSH (auto-rollbacks on syntax error).
- `mbf::security::install_fail2ban` — Install and enable `fail2ban`.
- `mbf::security::fw_backend` — Detect `ufw`, `firewalld`, or `iptables` (or `MBF_FIREWALL_BACKEND`).
- `mbf::security::fw_allow <port> [tcp|udp]` / `mbf::security::fw_deny <port> [tcp|udp]`
- `mbf::security::fw_enable_baseline [ssh_port]` — Allow SSH, HTTP (`80`), and HTTPS (`443`), then enable firewall default-deny incoming policy.

---

## 4. `webserver` `[••]` — Nginx Vhosts, SSL Lifecycle & Application Stacks
Provisions Nginx virtual hosts using `lib/templates/nginx/*.tpl` (customizable via `MBF_TEMPLATE_PATH`), manages Let's Encrypt or self-signed SSL certificates, and deploys PHP-FPM, Git, or WordPress stacks.

### Functions
- **Nginx Virtual Hosts**:
  - `mbf::webserver::ensure_nginx`
  - `mbf::webserver::vhost_static <domain> <root_dir>`
  - `mbf::webserver::vhost_php <domain> <root_dir> [php_version]`
  - `mbf::webserver::vhost_proxy <domain> <upstream_port>`
  - `mbf::webserver::vhost_remove <domain>`
- **SSL Certificates**:
  - `mbf::webserver::ssl_letsencrypt <domain> <email> [webroot_dir]`
  - `mbf::webserver::ssl_self_signed <domain> <dest_dir> [days]`
  - `mbf::webserver::ssl_expiry_days <pem_file_or_domain>`
  - `mbf::webserver::ssl_check_renewals [certs_dir] [warn_days]`
- **Application Stacks**:
  - `mbf::webserver::ensure_php [php_version] [extra_exts...]`
  - `mbf::webserver::deploy_git <app_dir> <repo_url> [branch] [build_cmd]`
  - `mbf::webserver::install_wordpress <domain> <root_dir> <db_name> <db_user> <db_pass> [php_ver]`

---

## 5. `database` `[••]` — MySQL, PostgreSQL, Redis & Backup Rotation
Provisions database engines, creates databases and least-privilege users, dumps/restores compressed SQL archives, and manages directory backups with `.sha256` manifests.

### Functions
- `mbf::database::ensure_mysql` / `mbf::database::ensure_postgres` / `mbf::database::ensure_redis`
- `mbf::database::create_db_and_user <mysql|postgres> <db_name> <db_user> <db_pass>`
- `mbf::database::dump <mysql|postgres> <db_name> <out_file.sql.gz>`
- `mbf::database::restore <mysql|postgres> <db_name> <in_file>`
- `mbf::database::archive_dir <src_dir> <dest_dir> [prefix]` — Create timestamped `.tar.gz` + `.sha256` manifest.
- `mbf::database::prune_backups <backup_dir> [keep_days]` — Delete archives older than `<keep_days>`.

---

## 6. `cron` `[••]` — Tagged Idempotent Crontab Manager
Manages cron jobs by unique `# mbf:id=<job_id>` tags without disturbing unmanaged user cron entries, and wraps scheduled jobs in non-overlapping locks.

### Functions
- `mbf::cron::set <job_id> "<schedule>" "<command>" [user]`
- `mbf::cron::remove <job_id> [user]`
- `mbf::cron::disable <job_id> [user]` / `mbf::cron::enable <job_id> [user]`
- `mbf::cron::list [user]`
- `mbf::cron::run_guarded <job_id> <cmd> [args...]` — Execute `<cmd>` inside `mbf::exec::lock_acquire`, log execution duration, and trigger `mbf::monitor::alert` on failure.

---

## 7. `runtime` `[•]` — Polyglot Node.js, Python & Binary Integration
Integrates external system tools, Node.js scripts, and Python scripts into `mbf` workflows, and automatically packages referenced `.js`/`.py` files and `INSTALL.md` when exported via `mbf export`.

### Functions
- `mbf::runtime::install_hint <pkg_name> [download_url]`
- `mbf::runtime::ensure_pkg <pkg_name> [cmd_name] [download_url]` (auto-installs if `MBF_AUTO_INSTALL=1`)
- `mbf::runtime::download <url> <dest_path> [expected_sha256]`
- `mbf::runtime::check_node [min_major]` / `mbf::runtime::npm_install [dir]` / `mbf::runtime::run_node <script.js> [args...]`
- `mbf::runtime::check_python [min_major]` / `mbf::runtime::pip_install [requirements.txt] [venv]` / `mbf::runtime::run_python <script.py> [args...]`

---

## 8. `obfuscator` `[•]` — Bash Script Obfuscation Add-on
Wraps `bash-obfuscate` to obfuscate exported standalone scripts prior to distribution or binary compilation (`mbf compile --obfuscate`).

### Functions
- `mbf::obfuscator::run <input.sh> [output.sh]`
