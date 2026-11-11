# Case Study 3: Refactoring Repetitive DevOps & Magento 2 Scripts with MBF

## Problem Statement
Managing a Magento 2 and CI/CD infrastructure often leads to a dozen separate Bash scripts—Docker environment setup, Magento 2 deployment, MFTF configuration, `deployer.php` (`dep`) workflows, Jenkins build triggers, Varnish cache warming, and server audits—each duplicating argument parsing, SSH/curl wrappers, lock files, and error handling.

---

## MBF Architecture & Solution

Instead of maintaining isolated scripts with duplicated boilerplate, structure your repository into:
1. **Reusable Custom Extensions (`plugins/magento.sh` & `plugins/devops.sh`)**: Created with `mbf new --ext` and validated with `mbf doctor`.
2. **Custom Project Templates (`templates/magento/`)**: `.env` and MFTF configuration templates rendered via `mbf::template::render`.
3. **AI-Assisted Failure Diagnosis (`plugins/ai.sh`)**: Automatically pipes failed Jenkins console outputs, `deployer.php` logs, or server audits into `claude`, `agy`, or `codex` via `mbf::ai::analyze`.

```text
magento-ops/
├── plugins/
│   ├── magento.sh                # Shared Magento 2 & MFTF functions (`mbf::magento::*`)
│   └── devops.sh                 # Shared Deployer, Jenkins & Varnish functions (`mbf::devops::*`)
├── templates/
│   └── magento/
│       ├── docker-compose.yml.tpl
│       └── mftf.env.tpl
├── m2-docker-setup.sh
├── m2-deploy.sh
├── varnish-warm.sh
└── server-audit-ai.sh
```

---

## 1. Custom Extension: `plugins/magento.sh`

```bash
#!/usr/bin/env bash
# @mbf-module: magento
# @mbf-rank: ••
# mbf:requires log exec config template net
# ==============================================================================
# Custom mbf Extension: magento
# Magento 2 Docker Setup, Zero-Downtime Deployment, and MFTF Configuration
# ==============================================================================

# Setup local Magento 2 Docker stack (PHP-FPM, Nginx, MariaDB, Redis, OpenSearch, Varnish)
# Usage: mbf::magento::docker_up <project_dir> <domain> [php_version]
function mbf::magento::docker_up() {
    local proj_dir="$1"
    local domain="$2"
    local php_ver="${3:-8.2}"

    mbf::template::render "magento/docker-compose.yml.tpl" "${proj_dir}/docker-compose.yml" \
        "DOMAIN=${domain}" \
        "PHP_VERSION=${php_ver}" || return 1

    mbf::config::ensure "/etc/hosts" "127.0.0.1 ${domain}"
    mbf::exec::run docker compose -f "${proj_dir}/docker-compose.yml" up -d
    mbf::net::wait_port 3306 "127.0.0.1" 60 || return 1
    mbf::net::wait_port 9200 "127.0.0.1" 60 || return 1
    mbf::log::ok "Magento 2 Docker stack is up at https://${domain}"
}

# Configure Magento Functional Testing Framework (MFTF) `.env` and build project
# Usage: mbf::magento::configure_mftf <magento_root> <base_url> <backend_name>
function mbf::magento::configure_mftf() {
    local m2_root="$1"
    local base_url="$2"
    local admin_path="${3:-admin}"
    local mftf_env="${m2_root}/dev/tests/acceptance/.env"

    mbf::template::render "magento/mftf.env.tpl" "$mftf_env" \
        "MAGENTO_BASE_URL=${base_url}" \
        "MAGENTO_BACKEND_NAME=${admin_path}" || return 1

    mbf::net::wait_port 4444 "127.0.0.1" 30 || mbf::log::warn "Selenium port 4444 not yet listening"
    mbf::exec::run "${m2_root}/vendor/bin/mftf" build:project
}
```

---

## 2. Custom Extension: `plugins/devops.sh` (Deployer.php, Jenkins & Varnish)

```bash
#!/usr/bin/env bash
# @mbf-module: devops
# @mbf-rank: ••
# mbf:requires log exec net json ai
# ==============================================================================
# Custom mbf Extension: devops
# Deployer.php CI/CD, Jenkins Build Runner, and Sitemap Varnish Cache Warmer
# ==============================================================================

# Run Deployer (`dep deploy`) with concurrency lock and automatic rollback on failure
# Usage: mbf::devops::dep_deploy <stage> [branch]
function mbf::devops::dep_deploy() {
    local stage="$1"
    local branch="${2:-main}"

    mbf::exec::lock_acquire "dep_${stage}" 10 || return 1
    mbf::log::info "Starting Deployer.php deployment to '${stage}' (branch: ${branch})..."

    if ! mbf::exec::run dep deploy "$stage" -o branch="$branch"; then
        mbf::log::error "Deployment failed on '${stage}' — triggering automatic rollback!"
        mbf::exec::run dep rollback "$stage"
        mbf::exec::lock_release "dep_${stage}"
        return 1
    fi

    mbf::exec::lock_release "dep_${stage}"
    mbf::log::ok "Deployment to '${stage}' succeeded."
}

# Warm Varnish cache by crawling URLs from a sitemap.xml
# Usage: mbf::devops::warm_varnish <sitemap_url> [max_urls]
function mbf::devops::warm_varnish() {
    local sitemap_url="$1"
    local max_urls="${2:-200}"

    mbf::log::info "Fetching sitemap from ${sitemap_url}..."
    local xml urls url count=0
    xml="$(mbf::net::request GET "$sitemap_url")" || return 1
    urls="$(printf '%s\n' "$xml" | grep -oE '<loc>[^<]+</loc>' | sed -e 's/<loc>//' -e 's/<\/loc>//' | head -n "$max_urls")"

    for url in $urls; do
        mbf::net::status_code "$url" 5 >/dev/null && count=$((count + 1))
    done
    mbf::log::ok "Warmed ${count} URLs in Varnish cache."
}

# Trigger a Jenkins job and analyze failure logs with AI CLI if the build fails
# Usage: mbf::devops::jenkins_build <job_url> <user_token>
function mbf::devops::jenkins_build() {
    local job_url="${1%/}"
    local auth="$2"

    mbf::log::info "Triggering Jenkins job: ${job_url}/build"
    mbf::exec::run curl -fsSL -X POST -u "$auth" "${job_url}/build" || return 1

    # If latest build failed, pipe consoleText into `mbf::ai::analyze`
    local status_json result console_out
    status_json="$(curl -fsSL -u "$auth" "${job_url}/lastBuild/api/json" 2>/dev/null)"
    result="$(mbf::json::get "$status_json" "result")"

    if [ "$result" == "FAILURE" ]; then
        mbf::log::error "Jenkins build failed — running AI root-cause diagnosis..."
        console_out="$(curl -fsSL -u "$auth" "${job_url}/lastBuild/consoleText" 2>/dev/null | tail -n 80)"
        mbf::ai::analyze "$console_out" "Identify why this Jenkins CI build failed and give the exact fix."
        return 1
    fi
    return 0
}
```

---

## 3. AI-Powered Server Audit Script (`server-audit-ai.sh`)

```bash
#!/usr/bin/env bash
source "${MBF_HOME:-$(dirname "$(command -v mbf)")/..}/framework.sh"
mbf::use log args exec monitor security ai

USAGE="Usage: $(basename "$0") [--ai-review]"
mbf::args::flag "a" "ai-review" "OPT_AI" "Analyze audit report with AI CLI (claude/agy/codex)"

function main() {
    mbf::args::parse "$@" || return 1

    local report_file
    mbf::exec::tmpfile report_file

    {
        mbf::monitor::report
        mbf::security::audit_ssh
        mbf::security::audit_system
    } | tee "$report_file"

    if [ "$OPT_AI" == "1" ]; then
        mbf::log::info "Running AI diagnosis on server audit report..."
        mbf::ai::analyze "$report_file" \
            "Review this Linux server performance and security report. List the top 3 bottlenecks or security risks and the exact commands to fix them."
    fi
}

main "$@"
```

### Validating & Exporting Your Custom Scripts
```bash
# 1. Verify extensions and templates pass all MBF compliance rules
mbf doctor plugins/magento.sh
mbf doctor plugins/devops.sh

# 2. Export standalone scripts for any target server or CI runner
mbf export server-audit-ai.sh -o dist/server-audit-ai.sh
```
