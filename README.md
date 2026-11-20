# MBF — Micro Bash Framework

> **A clean, modular, zero-bloat Bash framework that is easy to learn, easy to use, and easy to understand.**

`mbf` turns fragile, copy-pasted shell scripts into structured, maintainable, and distributable automation—without adding runtime dependencies or hiding native Bash behind heavy abstractions.

---

## Why MBF?

1. **Zero Bloat, Native First**: If native Bash 4+ already does something in one expression (`${var,,}`, `${var//a/b}`), `mbf` stays out of your way. Every function in `mbf` solves a real operational problem.
2. **Tree-Shaken Standalone Export (`mbf export`)**: Write modular code using `mbf::use`, then compile your script into a **single zero-dependency `.sh` file** (or full app bundle) containing *only* the functions your script actually calls.
3. **Production Safety by Default**: Built-in strict mode (`mbf::strict`), `--dry-run` simulation (`MBF_DRYRUN=1`), declarative CLI flags with automatic `--help`, non-overlapping concurrency locks, idempotent config edits, and automatic `.mbf.bak` backup/rollback.
4. **Write Once, Run Anywhere**: Unified environment, privilege, path prefix, and package manager abstractions across **Linux**, **macOS**, **Windows Git Bash**, **WSL**, and **Android Termux**.
5. **AI & Remote-Ops Ready**: Native integration with AI CLIs and OpenAI-compatible HTTP APIs (with automatic secret redaction and safe human-in-the-loop execution), plus agentless SSH script streaming (`mbf remote --self-remove`) and Capistrano/Deployer-style atomic zero-downtime releases (`plugins/deploy.sh`).
6. **Infinitely Extensible**: Drop custom project libraries (`lib/`), plugins (`plugins/`), and `.tpl` templates (`templates/`) right next to your script—verified by `mbf doctor` and runtime `[EXT-DEBUG]` tracing.

---

## 60-Second Quick Start

### 1. Install
```bash
# Option 1: One-Line Remote Install (Recommended — supports `--version v1.0.0`)
curl -fsSL https://raw.githubusercontent.com/ndthanhcom/mbf/master/install.sh | bash
# Or pinned to an exact release tag:
curl -fsSL https://raw.githubusercontent.com/ndthanhcom/mbf/v1.0.0/install.sh | bash -s -- --version v1.0.0

# Option 2: Git Clone + Standard Install
git clone https://github.com/ndthanhcom/mbf.git ~/.mbf
~/.mbf/install.sh
```

### 2. Create a Script (`mbf new deploy.sh`)
```bash
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::strict
mbf::use log args exec config

USAGE="Usage: $(basename "$0") [options]"
mbf::args::flag   "n" "dry-run" "MBF_DRYRUN" "Preview changes without modifying files"
mbf::args::option "d" "domain"  "OPT_DOMAIN" "Application domain" "app.example.com"

function main() {
    mbf::args::parse "$@" || return 1

    mbf::log::info "Configuring domain: ${OPT_DOMAIN}"
    mbf::config::ensure "/etc/hosts" "127.0.0.1 ${OPT_DOMAIN}"
    mbf::exec::run systemctl reload nginx
    mbf::log::ok "Deployment complete!"
}

main "$@"
```

### 3. Run or Export to a Standalone File
```bash
# 1. Auto-generated help table
./deploy.sh --help

# 2. Preview safely in dry-run mode (no files or services modified)
./deploy.sh --dry-run --domain shop.example.com

# 3. Export a tree-shaken, zero-dependency standalone script for any target server
mbf export deploy.sh -o dist/deploy.sh
```

---

## Module Overview

Click any module name for its **detailed function-by-function guide and code examples**:

### Core Libraries (`lib/`) — [Overview Index (`docs/LIBRARIES.md`)](docs/LIBRARIES.md)
| Library | Detailed Guide & Examples | Purpose |
| :--- | :--- | :--- |
| **`framework`** | [`docs/libraries/framework.md`](docs/libraries/framework.md) | Core loader (`mbf::use`), `mbf::strict`, `mbf::is_dryrun`, `mbf::version` & monthly update check |
| **`log`** | [`docs/libraries/log.md`](docs/libraries/log.md) | Structured logging (text/JSON/CI), TTY auto-color, secret redaction, stack traces & file sink |
| **`args`** | [`docs/libraries/args.md`](docs/libraries/args.md) | Declarative CLI flags (`--no-flag`), options, `require`, subcommand dispatch & auto `--help` |
| **`exec`** | [`docs/libraries/exec.md`](docs/libraries/exec.md) | Dry-run runner, exponential retry, `timeout`, `confirm`, `EXIT`/`INT`/`TERM` traps, locks & steps |
| **`ssh`** | [`docs/libraries/ssh.md`](docs/libraries/ssh.md) | Agentless SSH (`--self-remove`), `check`, `prompt`, password/key auth, ControlMaster mux, download/sync & multi-host |
| **`system`** | [`docs/libraries/system.md`](docs/libraries/system.md) | Cross-env detection (`linux`/`macos`/`gitbash`/`wsl`/`termux`), packages, services, users & checks |
| **`config`** | [`docs/libraries/config.md`](docs/libraries/config.md) | Idempotent KV/directive/block edits, `.mbf.bak` rollback, safe `load_env` & `*_FILE` secret reader |
| **`template`** | [`docs/libraries/template.md`](docs/libraries/template.md) | `.tpl` resolver, `# @mbf-vars:`, `{{VAR:-default}}`, `{{#if}}` blocks, `render_stdout`, `vars` & `diff` |
| **`json`** | [`docs/libraries/json.md`](docs/libraries/json.md) | Zero-dependency JSON `object`/`array_raw`/`merge`, `get` (with default), `has`, `is_valid` & `pretty` |
| **`net`** | [`docs/libraries/net.md`](docs/libraries/net.md) | HTTP client (`get`/`fetch`/auth/query builder), atomic SHA-256 downloads, TCP/HTTP polling, DNS & TLS expiry |
| **`str`** | [`docs/libraries/str.md`](docs/libraries/str.md) | `trim`, `slugify`, `snake`, `urlencode`/`b64`, `uuid`, `mask`, `join`/`split`, `truncate`, `between`, `escape_regex`, `sha256` & `hmac` |

### Plugins (`plugins/`) — [Overview Index (`docs/PLUGINS.md`)](docs/PLUGINS.md)
| Plugin | Detailed Guide & Examples | Purpose |
| :--- | :--- | :--- |
| **`ai`** | [`docs/plugins/ai.md`](docs/plugins/ai.md) | AI CLI & OpenAI-compatible HTTP API integration with secret redaction, JSON mode & safe `ai::run` |
| **`deploy`** | [`docs/plugins/deploy.md`](docs/plugins/deploy.md) | Capistrano / Deployer.php-style atomic zero-downtime releases, shared dirs, locks & instant rollback |
| **`notify`** | [`docs/plugins/notify.md`](docs/plugins/notify.md) | Multi-channel alerts (Email, Slack, Telegram) & HMAC-SHA256 signed SaaS webhooks |
| **`cron`** | [`docs/plugins/cron.md`](docs/plugins/cron.md) | Tagged idempotent crontab management (`# mbf:id=`) & non-overlapping guarded execution |
| **`backup`** | [`docs/plugins/backup.md`](docs/plugins/backup.md) | Timestamped `.tar.gz` directory archiving, `.sha256` manifest verification & retention pruning |

> Install domain-specific plugin & script repositories (such as Linux server audit/hardening or web-stack packs) on demand via `mbf plugin add github.com/<owner>/<repo>`.

---

## Documentation & Case Studies

- **[Core Libraries Index (`docs/LIBRARIES.md`)](docs/LIBRARIES.md)** & **[Per-Library Guides (`docs/libraries/`)](docs/libraries/)**
- **[Plugins Index (`docs/PLUGINS.md`)](docs/PLUGINS.md)** & **[Per-Plugin Guides (`docs/plugins/`)](docs/plugins/)**
- **[Extending MBF (`docs/EXTENDING.md`)](docs/EXTENDING.md)** — How to create export-compatible custom libraries, plugins, and `.tpl` templates, and troubleshoot with `mbf doctor`.
- **Real-World Case Studies (`docs/case-studies/`)**:
  1. **[Cross-Environment Scripts](docs/case-studies/01-cross-environment-scripts.md)** — Writing portable scripts across Linux, macOS, Windows Git Bash, WSL, and Android Termux.
  2. **[Turnkey Server Provisioning](docs/case-studies/02-turnkey-server-provisioning.md)** — Bootstrapping a VPS with SSH hardening, firewall, Docker stacks, and cron jobs.
  3. **[DevOps & Magento 2 Automation](docs/case-studies/03-devops-and-magento2-automation.md)** — Refactoring Magento 2 Docker, Deployer.php CI/CD, MFTF, Jenkins builds, Varnish cache warming, and AI server audits.
  4. **[Agentless Remote Execution & Zero-Downtime Deploys](docs/case-studies/04-agentless-remote-and-zero-downtime-deploy.md)** — Using `mbf remote --self-remove` and `plugins/deploy.sh` for Capistrano/Deployer-style atomic releases.

---

## CI/CD & Container Usage

MBF is built to drop cleanly into CI/CD pipelines without installing PHP, Ruby, or Python runtimes.

### 1. GitHub Actions (`action.yml`)
Use MBF as a composite action to expose `mbf` on `PATH` and `MBF_HOME` in any workflow job (with optional user plugins):

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Install MBF on the runner (optionally install extra plugins)
      - uses: ndthanhcom/mbf@v1
        with:
          plugins: |
            https://github.com/your-org/mbf-plugin-webstack.git

      # Validate, export a standalone artifact, or run a deploy script
      - name: Validate & Deploy
        env:
          MBF_LOG_CI: "1"          # Emit GitHub Actions ::warning:: / ::error:: annotations
          MBF_NO_UPDATE_CHECK: "1" # Skip periodic update check in CI
        run: |
          mbf doctor scripts/deploy.sh
          ./scripts/deploy.sh release --branch "${GITHUB_REF_NAME}"
```

### 2. Minimal Alpine Docker Image (`Dockerfile`)
Run MBF scripts or CLI commands inside an isolated Alpine container (includes `bash`, `git`, `curl`, `openssh-client`, `rsync`, `openssl`, `jq`, and `mbf` on `PATH`):

```bash
# Build the lightweight Alpine MBF image
docker build -t mbf:1.0.0 .

# Run MBF CLI commands directly
docker run --rm mbf:1.0.0 list

# Mount your project and export a standalone script inside the container
docker run --rm -v "$PWD:/work" -w /work mbf:1.0.0 \
    export scripts/deploy.sh -o dist/deploy.sh
```

### 3. Generic CI Runners (GitLab CI, Jenkins, Bitbucket Pipelines)
Pin an exact release tag with `install.sh --version` for reproducible, supply-chain-safe builds:

```bash
curl -fsSL https://raw.githubusercontent.com/ndthanhcom/mbf/v1.0.0/install.sh | bash -s -- --version v1.0.0
export PATH="$HOME/.mbf/bin:$PATH"
mbf doctor scripts/deploy.sh && mbf export scripts/deploy.sh -o dist/deploy.sh
```

---

## CLI Reference (`bin/mbf`)

```text
mbf --init                                    Print path to framework.sh for sourcing
mbf version [check|update|change|list]        Show version, check updates, update, list tags, or change tag
mbf list                                      List all core libraries and plugins
mbf plugin <list|add|update|remove|run> [...] Manage plugin & script repositories (.installed_plugins)
mbf new [--ext] <name.sh>                     Scaffold a new mbf script or custom extension module
mbf doctor <script_or_ext.sh>                 Validate script, custom extensions & templates
mbf remote [--self-remove] <host> <script.sh> Export & run a local script agentlessly over SSH
mbf ai <ask|ask-json|analyze|cmd|run> [...]   Run AI log analysis, JSON queries, or safe command generation
mbf export <script.sh> [-o <out>] [-d <dir>]  Export tree-shaken standalone script or app bundle
mbf test [filter]                             Run the automated test suite
```
