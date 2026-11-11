# Case Study 2: Turnkey Server Provisioning (Hardening, Firewall, Docker, Nginx + SSL & Cronjobs)

## Problem Statement
Provisioning a bare Linux VPS into a production-ready application host requires coordinating multiple subsystems safely and idempotently:
- Hardening SSH (`PermitRootLogin no`, key-only auth) without locking out the operator.
- Enabling a firewall (`ufw`/`firewalld`) with SSH, HTTP (`80`), and HTTPS (`443`) open.
- Deploying a Docker Compose stack or PHP-FPM/WordPress application.
- Provisioning an Nginx virtual host and issuing a Let's Encrypt TLS certificate.
- Registering non-overlapping scheduled cron jobs for database backups and SSL renewal checks.
- Shipping the entire workflow as a **single zero-dependency script** to run on fresh servers where `mbf` is not installed.

---

## MBF Architecture & Solution

1. **Idempotent Step Checkpointing (`mbf::exec::step_run`)**: Ensures already-completed provisioning stages are skipped on re-run.
2. **SSH & Firewall Baseline (`plugins/security.sh`)**: `mbf::security::harden_ssh` backs up `sshd_config` and validates syntax via `sshd -t` before reloading; `mbf::security::fw_enable_baseline` opens `22`, `80`, and `443` before enabling the firewall.
3. **Template-Driven Nginx + SSL (`plugins/webserver.sh`)**: Renders Nginx configs atomically and provisions Let's Encrypt via Certbot.
4. **Guarded Cron Jobs (`plugins/cron.sh`)**: Registers tagged `# mbf:id=<job>` cron entries wrapped with `mbf::cron::run_guarded`.
5. **Standalone Export (`mbf export`)**: Compiles the script and only its called functions into a single distributable file.

---

## Complete Blueprint Script (`provision-server.sh`)

```bash
#!/usr/bin/env bash
source "${MBF_HOME:-$(dirname "$(command -v mbf)")/..}/framework.sh"
mbf::use log args exec system config security webserver database cron monitor

USAGE="Usage: $(basename "$0") --domain <domain> --email <admin_email> [options]"
mbf::args::flag   "n" "dry-run"  "MBF_DRYRUN" "Preview provisioning steps"
mbf::args::option "d" "domain"   "OPT_DOMAIN" "Primary website domain"
mbf::args::option "m" "email"    "OPT_EMAIL"  "Admin email for Let's Encrypt & alerts"
mbf::args::option "p" "app-port" "OPT_PORT"   "Upstream Docker container port" "8080"

function main() {
    mbf::args::parse "$@" || return 1

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

    # 3. Provision Nginx reverse-proxy vhost & Let's Encrypt SSL
    mbf::webserver::ensure_nginx
    mbf::webserver::vhost_proxy "$OPT_DOMAIN" "$OPT_PORT"
    mbf::webserver::ssl_letsencrypt "$OPT_DOMAIN" "$OPT_EMAIL"

    # 4. Configure idempotent cron jobs for backups and SSL renewal checks
    mbf::cron::set "nightly_backup" "0 3 * * *" "/usr/local/bin/backup-app.sh"
    mbf::cron::set "ssl_check"      "0 6 * * 1" "mbf monitor report >/var/log/mbf-weekly-review.log"

    # 5. Send SaaS completion event if webhook is configured
    if [ -n "${MBF_SAAS_WEBHOOK_URL:-}" ]; then
        mbf::monitor::send_event "prov_${OPT_DOMAIN}" "complete" "ok" "Server provisioned for ${OPT_DOMAIN}"
    fi

    mbf::log::ok "Server provisioning complete for https://${OPT_DOMAIN}"
}

main "$@"
```

### Exporting for Remote Execution
```bash
mbf export provision-server.sh -o dist/provision-server.sh
scp dist/provision-server.sh root@203.0.113.10:/root/
ssh root@203.0.113.10 "./provision-server.sh --domain app.example.com --email ops@example.com"
```
