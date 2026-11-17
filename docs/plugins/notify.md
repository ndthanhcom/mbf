# Plugin: `notify` `[•••]` — Multi-Channel Messaging, Alerts & Signed Webhooks

`plugins/notify.sh` dispatches operational notifications via Email, Slack, Telegram, and HMAC-SHA256 signed SaaS webhooks. All HTTP requests route through `mbf::net::post_json` and respect `MBF_DRYRUN=1`.

---

## Environment Variables

| Variable | Description |
| :--- | :--- |
| `MBF_MAIL_TO` | Default recipient email address for `email` and `alert`. |
| `MBF_MAIL_FROM` | Sender address (default: `mbf@<hostname>`). |
| `MBF_MAIL_CMD` | Optional custom mail binary/function receiving `<to>` and `<subject>` (with body on `stdin`). |
| `MBF_SLACK_WEBHOOK` | Slack Incoming Webhook URL. |
| `MBF_TELEGRAM_BOT_TOKEN` | Telegram Bot API token (`123456:ABC...`). |
| `MBF_TELEGRAM_CHAT_ID` | Telegram destination chat or channel ID (`-100...`). |
| `MBF_SAAS_WEBHOOK_URL` | SaaS webhook endpoint for `mbf::notify::webhook`. |
| `MBF_SAAS_SECRET` | Optional HMAC-SHA256 secret used to sign webhook payloads. |

---

## Function Reference & Examples

### 1. `mbf::notify::email <to> <subject> <body>`
Sends an email using the first available mail client (`MBF_MAIL_CMD`, `mail`, `mailx`, `sendmail`, or `msmtp`).

```bash
mbf::use notify

mbf::notify::email "ops@example.com" "[PROD] Backup Completed" "Database dump saved to /var/backups."
```

### 2. `mbf::notify::slack <message> [webhook_url]`
Posts a JSON message (`{"text":"..."}`) to a Slack Incoming Webhook URL (uses `$MBF_SLACK_WEBHOOK` when the 2nd argument is omitted).

```bash
export MBF_SLACK_WEBHOOK="https://hooks.slack.com/services/T000/B000/XXXX"
mbf::notify::slack "Magento 2 deployment v2.4.7 finished on prod-web01."
```

### 3. `mbf::notify::telegram <message> [bot_token] [chat_id]`
Sends a message via the Telegram Bot API (`sendMessage`). Uses `$MBF_TELEGRAM_BOT_TOKEN` and `$MBF_TELEGRAM_CHAT_ID` when arguments 2 and 3 are omitted.

```bash
export MBF_TELEGRAM_BOT_TOKEN="123456:ABC-DEF"
export MBF_TELEGRAM_CHAT_ID="-100987654321"
mbf::notify::telegram "High load average detected on prod-web01 (12.4)"
```

### 4. `mbf::notify::webhook <job_id> <step> <status> <message> [webhook_url]`
Sends a structured JSON telemetry event to `[webhook_url]` (or `$MBF_SAAS_WEBHOOK_URL`):
- Fields: `job_id`, `host`, `step`, `status`, `message`, `timestamp` (UTC ISO-8601), and `signature`.
- When `MBF_SAAS_SECRET` is set, `signature` contains the HMAC-SHA256 hex digest of `<job_id>:<step>:<status>:<timestamp>:<message>`.

```bash
export MBF_SAAS_WEBHOOK_URL="https://ops.example.com/api/v1/events"
export MBF_SAAS_SECRET="super_secret_hmac_key"

mbf::notify::webhook "deploy_20261116" "db_migrate" "completed" "Applied 4 schema migrations"
```

### 5. `mbf::notify::alert <title> <message>`
Broadcasts `[<title>] <message>` to **all** configured channels (`MBF_SLACK_WEBHOOK`, `MBF_TELEGRAM_*`, and `MBF_MAIL_TO`). Automatically invoked by `mbf::cron::run_guarded` when a scheduled job fails.

```bash
export MBF_SLACK_WEBHOOK="https://hooks.slack.com/services/T000/B000/XXXX"
export MBF_MAIL_TO="oncall@example.com"

mbf::notify::alert "Disk Space Alert" "Partition /var is at 94% capacity on prod-db01"
```
