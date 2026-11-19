# Case Study 04: Agentless Remote Execution & Zero-Downtime Deployments

This blueprint demonstrates how to replace heavy deployment runtimes (Deployer.php, Capistrano, or ad-hoc SSH loops) with **MBF's `lib/ssh.sh` + `plugins/deploy.sh` + `mbf remote`**, requiring **zero installation on target servers**.

---

## Scenario 1: Agentless One-Off Server Diagnostics (`mbf remote --self-remove`)

Write a clean, modular MBF script locally (`scripts/check_node.sh`) using `mbf::use monitor json`:

```bash
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::strict
mbf::use monitor json

mbf::monitor::collect_review_json
```

Run it on any remote server without installing `mbf` there—and with `--self-remove` so the temporary staged script deletes itself immediately on exit (even if an error occurs):

```bash
mbf remote --self-remove deploy@prod-web-01.example.com ./scripts/check_node.sh
```

What happens under the hood:
1. Local `mbf` tree-shakes `scripts/check_node.sh` into a minimal zero-dependency script via `mbf export`.
2. In a single SSH call, it stages the script into a `0700` remote `mktemp` file with an injected `EXIT` self-removal trap.
3. The script executes with a clean stdin (`</dev/null`) and real `$0`, prints the JSON snapshot, and deletes itself.

---

## Scenario 2: Multi-Host Atomic Zero-Downtime Deployment (`deploy.sh`)

Using `lib/args.sh` (subcommands + `--no-flag`), `lib/config.sh` (safe `.env` + `*_FILE` secret redaction), `lib/ssh.sh` (`ControlMaster` multiplexing), `plugins/deploy.sh`, `plugins/notify.sh`, and `plugins/ai.sh` (automated failure triage):

```bash
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::strict
mbf::use log args exec config ssh deploy notify ai

# Load deployment settings safely (no `source`/`eval`)
[ -f ".env.deploy" ] && mbf::config::load_env ".env.deploy" 0
[ -n "${MBF_SLACK_WEBHOOK:-}" ] && mbf::log::redact "$MBF_SLACK_WEBHOOK"

HOSTS=("deploy@web-01.example.com" "deploy@web-02.example.com")
DEPLOY_PATH="${DEPLOY_PATH:-/var/www/shop}"
REPO_URL="${REPO_URL:-git@github.com:acme/shop.git}"

MBF_DEPLOY_SHARED_FILES=(".env" "app/etc/env.php")
MBF_DEPLOY_SHARED_DIRS=("var/log" "pub/media")
MBF_DEPLOY_WRITABLE_DIRS=("var/cache" "var/page_cache")
MBF_DEPLOY_KEEP_RELEASES=5

USAGE="Usage: deploy.sh <command> [options]"
mbf::args::command "release"  "Deploy a new atomic release to all web nodes"
mbf::args::command "rollback" "Roll back all web nodes to the previous release"
mbf::args::command "releases" "List releases on all web nodes"

mbf::args::flag   "n" "dry-run" "MBF_DRYRUN" "Preview deployment without modifying servers"
mbf::args::option "b" "branch"  "OPT_BRANCH" "Git branch or tag to deploy" "main"

function cmd_release() {
    mbf::args::parse "$@" || return 1

    local host rel
    for host in "${HOSTS[@]}"; do
        mbf::log::info "=== Deploying ${OPT_BRANCH} to ${host} ==="
        mbf::ssh::open "$host"
        mbf::deploy::setup "$host" "$DEPLOY_PATH"
        mbf::deploy::lock  "$host" "$DEPLOY_PATH"

        rel="$(mbf::deploy::prepare "$host" "$DEPLOY_PATH")"
        mbf::deploy::fetch_git "$host" "$rel" "$REPO_URL" "$OPT_BRANCH"
        mbf::deploy::shared    "$host" "$DEPLOY_PATH" "$rel"
        mbf::deploy::writable  "$host" "$rel"

        # Application build step (runs over the multiplexed SSH session)
        mbf::ssh::run_bash "$host" '
            set -eu
            cd "$1"
            composer install --no-dev --optimize-autoloader
        ' "$rel"

        # Atomic symlink swap (`ln -s` + `mv -Tf`) — zero 404/502 window
        mbf::deploy::symlink "$host" "$DEPLOY_PATH" "$rel"
        mbf::ssh::run "$host" sudo systemctl reload php8.2-fpm nginx
        mbf::deploy::cleanup "$host" "$DEPLOY_PATH" "$MBF_DEPLOY_KEEP_RELEASES"
        mbf::deploy::unlock  "$host" "$DEPLOY_PATH"
        mbf::ssh::close "$host"
    done

    mbf::notify::alert "Deploy Complete" "Branch ${OPT_BRANCH} is live on ${HOSTS[*]}" || true
}

function cmd_rollback() {
    mbf::args::parse "$@" || return 1
    local host
    for host in "${HOSTS[@]}"; do
        mbf::ssh::open "$host"
        mbf::deploy::rollback "$host" "$DEPLOY_PATH"
        mbf::ssh::run "$host" sudo systemctl reload php8.2-fpm nginx
        mbf::ssh::close "$host"
    done
    mbf::notify::alert "Rollback Complete" "Rolled back ${HOSTS[*]} to previous release" || true
}

function cmd_releases() {
    mbf::args::parse "$@" || return 1
    local host
    for host in "${HOSTS[@]}"; do
        printf '\n[%s]\n' "$host"
        mbf::deploy::releases "$host" "$DEPLOY_PATH"
    done
}

mbf::args::dispatch "cmd" "$@"
```

### Usage

```bash
# Preview the entire rollout safely
./deploy.sh release --branch v2.4.0 --dry-run

# Deploy atomically to all nodes
./deploy.sh release --branch v2.4.0

# Inspect active & previous releases
./deploy.sh releases

# Instant <1s rollback if needed
./deploy.sh rollback
```
