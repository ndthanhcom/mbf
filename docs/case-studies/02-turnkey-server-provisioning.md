# Case Study 2: Turnkey Server Provisioning (Hardening, Firewall, Docker, Templates & Cronjobs)

## Problem Statement
Provisioning a bare Linux VPS into a production-ready application host requires coordinating multiple subsystems safely and idempotently:
- Hardening SSH (`PermitRootLogin no`, key-only auth) without locking out the operator.
- Enabling a firewall (`ufw`/`firewalld`) with SSH, HTTP (`80`), and HTTPS (`443`) open.
- Deploying a Docker Compose stack and rendering service configuration from a `.tpl` template.
- Registering non-overlapping scheduled cron jobs for backups and weekly health reports.
- Running the entire workflow **agentlessly on fresh servers** where `mbf` is not installed.

---

## MBF Architecture & Solution

1. **Idempotent Step Checkpointing (`mbf::exec::step_run`)**: Ensures already-completed provisioning stages are skipped on re-run (and never persisted during `--dry-run`).
2. **SSH & Firewall Baseline (`plugins/security.sh`)**: `mbf::security::harden_ssh` backs up `sshd_config`, updates active/commented directives safely, and validates syntax via `sshd -t` before reloading; `mbf::security::fw_enable_baseline` opens `22`, `80`, and `443` before enabling the firewall.
3. **Template-Driven Configs (`lib/template.sh`)**: Renders project `.tpl` files atomically with `# @mbf-vars:` validation.
4. **Guarded Cron Jobs & Notifications (`plugins/cron.sh` + `plugins/notify.sh`)**: Registers tagged `# mbf:id=<job>` cron entries and posts signed SaaS webhook events.
5. **Agentless Remote Execution (`mbf remote --self-remove`)**: Tree-shakes the script on the fly, runs it on the fresh VPS, and removes the staged temp file immediately on exit.

---

## Complete Blueprint Script (`provision-server.sh`)

```bash
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::strict
mbf::use log args exec system config template security backup cron notify

USAGE="Usage: $(basename "$0") --domain <domain> --email <admin_email> [options]"
mbf::args::flag   "n" "dry-run"  "MBF_DRYRUN" "Preview provisioning steps"
mbf::args::option "d" "domain"   "OPT_DOMAIN" "Primary website domain"
mbf::args::option "m" "email"    "OPT_EMAIL"  "Admin email for alerts"
mbf::args::option "p" "app-port" "OPT_PORT"   "Upstream Docker container port" "8080"

function main() {
    mbf::args::parse "$@" || return 1
    mbf::args::require OPT_DOMAIN "--domain" || return 1
    mbf::args::require OPT_EMAIL  "--email"  || return 1

    mbf::system::is_domain "$OPT_DOMAIN" || mbf::die "Valid --domain is required"
    mbf::system::is_email  "$OPT_EMAIL"  || mbf::die "Valid --email is required"

    # 1. Harden SSH & enable firewall baseline (SSH + 80 + 443)
    mbf::exec::step_run "01_harden_ssh"  mbf::security::harden_ssh "/etc/ssh/sshd_config" 1
    mbf::exec::step_run "02_firewall"    mbf::security::fw_enable_baseline 22
    mbf::exec::step_run "03_fail2ban"    mbf::security::install_fail2ban

    # 2. Install Docker & launch application stack
    mbf::exec::step_run "04_install_docker" mbf::system::pkg_install docker.io docker-compose-plugin
    mbf::system::service_ensure docker

    if [ -f "/opt/app/docker-compose.yml" ]; then
        mbf::exec::run docker compose -f /opt/app/docker-compose.yml up -d --remove-orphans
    fi

    # 3. Render reverse-proxy config from project `./templates/proxy.conf.tpl` if present
    if mbf::template::resolve "proxy.conf.tpl" >/dev/null 2>&1; then
        mbf::template::render "proxy.conf.tpl" "/etc/nginx/conf.d/${OPT_DOMAIN}.conf" \
            "DOMAIN=${OPT_DOMAIN}" \
            "UPSTREAM_PORT=${OPT_PORT}"
        mbf::system::service reload nginx
    fi

    # 4. Configure idempotent cron jobs for backups and weekly server reviews
    mbf::cron::set "nightly_backup" "0 3 * * *" "/usr/local/bin/backup-app.sh"
    mbf::cron::set "weekly_review"  "0 6 * * 1" "/usr/local/bin/weekly-review.sh"

    # 5. Send SaaS completion event if webhook is configured
    if [ -n "${MBF_SAAS_WEBHOOK_URL:-}" ]; then
        mbf::notify::webhook "prov_${OPT_DOMAIN}" "complete" "ok" "Server provisioned for ${OPT_DOMAIN}"
    fi

    mbf::log::ok "Server provisioning complete for https://${OPT_DOMAIN}"
}

main "$@"
```

### Running Agentlessly on a Fresh Server
```bash
# Option 1: Export, execute, and self-remove in a single command (zero MBF install on target)
mbf remote --self-remove root@203.0.113.10 ./provision-server.sh -- \
    --domain app.example.com --email ops@example.com

# Option 2: Export a standalone bundle to distribute via CI/CD
mbf export provision-server.sh --bundle-dir dist/provision
```
