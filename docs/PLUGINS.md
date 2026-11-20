# MBF Plugins Reference (`plugins/`)

Plugins provide higher-level operational capabilities for AI CLI/API integration, atomic zero-downtime deployments, multi-channel notifications, cron management, and directory backups. Load any plugin with `mbf::use <plugin>`.

Each section below summarizes the plugin's functions, provides a quick example, and links to its **detailed function-by-function guide** in [`docs/plugins/`](plugins/).

---

## 1. `ai` — AI CLI & OpenAI-Compatible HTTP API Integration
**Detailed Guide & Function Examples**: [`docs/plugins/ai.md`](plugins/ai.md)

Connects `mbf` scripts to AI CLIs (`agy`, `claude`, `gemini`, `codex`, `hermes`, `ollama`, `llm`) or HTTP APIs (`MBF_AI_BASE_URL` OpenAI-compatible, Gemini, Anthropic) with pre-send secret redaction, context size capping, JSON mode, and safe human-in-the-loop command execution.

### Functions
- `mbf::ai::detect` — Print the highest-priority available AI provider.
- `mbf::ai::ensure [provider]` — Verify an AI CLI is installed; print installation instructions if missing.
- `mbf::ai::ask "<prompt>" [context_file_or_dash]` — Run a one-shot prompt with automatic secret redaction (`MBF_AI_REDACT=1`), context size capping (`MBF_AI_MAX_CONTEXT_BYTES`), and `MBF_AI_TIMEOUT`.
- `mbf::ai::ask_json "<prompt>" [context_file_or_dash]` — Request a validated raw JSON response for DevOps script branching.
- `mbf::ai::analyze <file_or_dash_or_text> [instruction]` — Send a log file, piped `stdin` (`-`), or text to the AI provider for root-cause analysis.
- `mbf::ai::cmd "<task_description>"` — Request a raw executable bash command (markdown fences stripped).
- `mbf::ai::run "<task_description>"` — Safe human-in-the-loop command runner (`mbf::ai::cmd` + `mbf::exec::confirm` + `mbf::exec::run`).

```bash
mbf::use ai
mbf::ai::analyze "/var/log/nginx/error.log" "Diagnose 502 Bad Gateway errors and recommend fixes."
```

---

## 2. `deploy` — Atomic Zero-Downtime Remote Releases (Capistrano / Deployer Style)
**Detailed Guide & Function Examples**: [`docs/plugins/deploy.md`](plugins/deploy.md)

Implements Capistrano / Deployer.php-style atomic symlink deployments over SSH (`releases/`, `shared/`, `current`, `.dep/deploy.lock`) with instant rollback and release cleanup.

### Functions
- `mbf::deploy::setup <host> <deploy_path>` — Initialize `releases/`, `shared/`, and `.dep/` directories.
- `mbf::deploy::lock <host> <deploy_path> [who]` / `mbf::deploy::unlock <host> <deploy_path>` — Atomic remote deployment lock with automatic `on_exit` release.
- `mbf::deploy::prepare <host> <deploy_path> [release_id]` — Create timestamped release directory and print its path.
- `mbf::deploy::fetch_git <host> <release_path> <repo_url> [branch]` / `mbf::deploy::upload_release <host> <local_dir> <release_path> [rsync_args...]` — Populate release via Git or CI artifact rsync.
- `mbf::deploy::shared <host> <deploy_path> <release_path>` / `mbf::deploy::writable <host> <release_path> [mode]` — Symlink shared files/dirs and apply writable permissions.
- `mbf::deploy::symlink <host> <deploy_path> <release_path>` — Atomically switch `current` symlink (`mv -Tf`).
- `mbf::deploy::cleanup <host> <deploy_path> [keep]` — Prune old releases while protecting active `current`.
- `mbf::deploy::rollback <host> <deploy_path> [release_id]` / `mbf::deploy::releases <host> <deploy_path>` — Instant rollback and release listing.

```bash
mbf::use ssh deploy
mbf::ssh::open "deploy@web-01"
mbf::deploy::setup "deploy@web-01" "/var/www/app"
rel="$(mbf::deploy::prepare "deploy@web-01" "/var/www/app")"
mbf::deploy::fetch_git "deploy@web-01" "$rel" "git@github.com:acme/app.git" "main"
mbf::deploy::symlink "deploy@web-01" "/var/www/app" "$rel"
```

---

## 3. `notify` — Multi-Channel Messaging, Alerts & Signed Webhooks
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

## 4. `cron` — Tagged Idempotent Crontab Manager
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

## 5. `backup` — Directory Archiving, Checksum Verification & Retention Pruning
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

## External & Community Plugins (`mbf plugin`)

Domain-specific or OS-specific plugins and extended scripts (such as Linux server audit/hardening or web-stack packs) live in separate repositories and are managed via `.installed_plugins` with automatic `README.md` manifest & `mbf-compat` version checking:

```bash
mbf plugin add github.com/<owner>/<repo>         # Install plugin/script repo (checks mbf-compat)
mbf plugin list                                  # List tracked installed packages
mbf plugin update [package_name]                 # Update one or all installed git repos
mbf plugin run <package_name> <script.sh> [...]  # Execute an extended script from an installed repo
mbf plugin remove <package_name>                 # Cleanly remove package, plugins & templates
```

See [`docs/EXTENDING.md`](EXTENDING.md) for the `README.md` manifest table specification.
