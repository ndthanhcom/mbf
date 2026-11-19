# MBF — Micro Bash Framework

> **A clean, modular, zero-bloat Bash framework that is easy to learn, easy to use, and easy to understand.**

`mbf` turns fragile, copy-pasted shell scripts into structured, maintainable, and distributable automation—without adding runtime dependencies or hiding native Bash behind heavy abstractions.

---

## Why MBF?

1. **Zero Bloat, Native First**: If native Bash 4+ already does something in one expression (`${var,,}`, `${var//a/b}`), `mbf` stays out of your way. Every function in `mbf` solves a real operational problem.
2. **Tree-Shaken Standalone Export (`mbf export`)**: Write modular code using `mbf::use`, then compile your script into a **single zero-dependency `.sh` file** (or full app bundle) containing *only* the functions your script actually calls.
3. **Production Safety by Default**: Built-in strict mode (`mbf::strict`), `--dry-run` simulation (`MBF_DRYRUN=1`), declarative CLI flags with automatic `--help`, non-overlapping concurrency locks, idempotent config edits, and automatic `.mbf.bak` backup/rollback.
4. **Write Once, Run Anywhere**: Unified environment, privilege, path prefix, and package manager abstractions across **Linux**, **macOS**, **Windows Git Bash**, **WSL**, and **Android Termux**.
5. **AI & Polyglot Ready**: Native integration with mainstream AI CLI tools (`claude`, `agy`, `gemini`, `codex`) for intelligent log/server analysis, plus seamless Node.js and Python execution and bundling.
6. **Infinitely Extensible**: Drop custom project libraries (`lib/`), plugins (`plugins/`), and `.tpl` templates (`templates/`) right next to your script—verified by `mbf doctor` and runtime `[EXT-DEBUG]` tracing.

---

## 60-Second Quick Start

### 1. Install
```bash
# Option 1: One-Line Remote Install (Recommended)
curl -fsSL https://raw.githubusercontent.com/ndthanhcom/mbf/master/install.sh | bash

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

## Module Overview & Importance Ranking

Modules are ranked from **`••••` (Essential)** to **`•` (Specialized)** to guide inclusion when authoring scripts. Click any module name for its **detailed function-by-function guide and code examples**:

### Core Libraries (`lib/`) — [Overview Index (`docs/LIBRARIES.md`)](docs/LIBRARIES.md)
| Library | Rank | Detailed Guide & Examples | Purpose |
| :--- | :--- | :--- | :--- |
| **`framework`** | `••••` | [`docs/libraries/framework.md`](docs/libraries/framework.md) | Core loader (`mbf::use`), `mbf::strict`, `mbf::is_dryrun`, `mbf::version` & monthly update check |
| **`log`** | `••••` | [`docs/libraries/log.md`](docs/libraries/log.md) | Structured terminal logging, file logging, stack traces & `[EXT-DEBUG]` diagnostics |
| **`args`** | `••••` | [`docs/libraries/args.md`](docs/libraries/args.md) | Declarative CLI flags, options, defaults, `--` handling & automatic `--help` generation |
| **`exec`** | `••••` | [`docs/libraries/exec.md`](docs/libraries/exec.md) | Dry-run command runner, retries, LIFO `EXIT` traps, auto-cleaned temp files, locks & step checkpoints |
| **`system`** | `•••` | [`docs/libraries/system.md`](docs/libraries/system.md) | Cross-env detection (`linux`/`macos`/`gitbash`/`wsl`/`termux`), packages, services, users & checks |
| **`config`** | `•••` | [`docs/libraries/config.md`](docs/libraries/config.md) | Idempotent KV, directive, line, and multi-line block config mutations + `.mbf.bak` rollback |
| **`template`** | `•••` | [`docs/libraries/template.md`](docs/libraries/template.md) | Convention-based `.tpl` resolver (user override + built-in), `# @mbf-vars:` check & `{{VAR}}` renderer |
| **`json`** | `•••` | [`docs/libraries/json.md`](docs/libraries/json.md) | Zero-dependency JSON escaping, object/array builder & scalar key extractor |
| **`net`** | `•••` | [`docs/libraries/net.md`](docs/libraries/net.md) | HTTP/REST client, atomic SHA-256 verified downloads, TCP port polling & DNS/IP lookup |
| **`ssh`** | `•••` | [`docs/libraries/ssh.md`](docs/libraries/ssh.md) | Agentless SSH remote execution, ControlMaster multiplexing, rsync & tree-shaken script streaming |
| **`str`** | `••` | [`docs/libraries/str.md`](docs/libraries/str.md) | String `trim`, `slugify`, cryptographic `random`, `sha256`, `verify_sha256` & `hmac_sha256` |

### Plugins (`plugins/`) — [Overview Index (`docs/PLUGINS.md`)](docs/PLUGINS.md)
| Plugin | Rank | Detailed Guide & Examples | Purpose |
| :--- | :--- | :--- | :--- |
| **`deploy`** | `•••` | [`docs/plugins/deploy.md`](docs/plugins/deploy.md) | Capistrano / Deployer.php-style atomic zero-downtime releases, shared dirs, locks & instant rollback |
| **`ai`** | `•••` | [`docs/plugins/ai.md`](docs/plugins/ai.md) | Mainstream AI CLI integration (`claude`, `agy`, `gemini`, `codex` + secondary/HTTP fallbacks) |
| **`monitor`** | `•••` | [`docs/plugins/monitor.md`](docs/plugins/monitor.md) | Server resource, performance, log, firewall, cron & command history auditing + JSON snapshots |
| **`notify`** | `•••` | [`docs/plugins/notify.md`](docs/plugins/notify.md) | Multi-channel alerts (Email, Slack, Telegram) & HMAC-SHA256 signed SaaS webhooks |
| **`security`** | `•••` | [`docs/plugins/security.md`](docs/plugins/security.md) | SSH & `sshd_config.d` drop-in auditing/hardening, UID 0 audit & UFW/firewalld/iptables management |
| **`webserver`** | `••` | [`docs/plugins/webserver.md`](docs/plugins/webserver.md) | Template-driven Nginx vhosts (with `nginx -t` rollback), Let's Encrypt/self-signed SSL, PHP-FPM & Git |
| **`database`** | `••` | [`docs/plugins/database.md`](docs/plugins/database.md) | MySQL/PostgreSQL/Redis provisioning, least-privilege users & atomic compressed SQL dump/restore |
| **`backup`** | `••` | [`docs/plugins/backup.md`](docs/plugins/backup.md) | Timestamped `.tar.gz` directory archiving, `.sha256` manifest verification & retention pruning |
| **`cron`** | `••` | [`docs/plugins/cron.md`](docs/plugins/cron.md) | Tagged idempotent crontab management (`# mbf:id=`) & non-overlapping guarded execution |
| **`runtime`** | `•` | [`docs/plugins/runtime.md`](docs/plugins/runtime.md) | Polyglot Node.js, Python & external binary runner and automatic bundle packager |
| **`obfuscator`** | `•` | [`docs/plugins/obfuscator.md`](docs/plugins/obfuscator.md) | Bash script obfuscation add-on (`bash-obfuscate` wrapper) |

---

## Documentation & Case Studies

- **[Core Libraries Index (`docs/LIBRARIES.md`)](docs/LIBRARIES.md)** & **[Per-Library Guides (`docs/libraries/`)](docs/libraries/)**
- **[Plugins Index (`docs/PLUGINS.md`)](docs/PLUGINS.md)** & **[Per-Plugin Guides (`docs/plugins/`)](docs/plugins/)**
- **[Extending MBF (`docs/EXTENDING.md`)](docs/EXTENDING.md)** — How to create export-compatible custom libraries, plugins, and `.tpl` templates, and troubleshoot with `mbf doctor`.
- **Real-World Case Studies (`docs/case-studies/`)**:
  1. **[Cross-Environment Scripts](docs/case-studies/01-cross-environment-scripts.md)** — Writing portable scripts across Linux, macOS, Windows Git Bash, WSL, and Android Termux.
  2. **[Turnkey Server Provisioning](docs/case-studies/02-turnkey-server-provisioning.md)** — Bootstrapping a VPS with SSH hardening, firewall, Docker stacks, Nginx + SSL, and cron jobs.
  3. **[DevOps & Magento 2 Automation](docs/case-studies/03-devops-and-magento2-automation.md)** — Refactoring Magento 2 Docker, Deployer.php CI/CD, MFTF, Jenkins builds, Varnish cache warming, and AI server audits.

---

## CLI Reference (`bin/mbf`)

```text
mbf --init                                    Print path to framework.sh for sourcing
mbf list                                      List all libraries and plugins with [••••] ranks
mbf new [--ext] <name.sh>                     Scaffold a new mbf script or custom extension module
mbf doctor <script_or_ext.sh>                 Validate script, custom extensions & templates
mbf remote [--self-remove] <host> <script.sh> Export & run a local script agentlessly over SSH
mbf export <script.sh> [-o <out>] [-d <dir>]  Export tree-shaken standalone script or app bundle
mbf compile <script.sh> [-o <bin>]            Compile exported script into a binary via shc
mbf monitor [check]                           Run server monitoring report (all, resources, logs, etc.)
mbf update [branch]                           Update mbf via git pull
mbf test [filter]                             Run the automated test suite
mbf --version                                 Print current mbf version
```

---

## Repository Structure

```text
mbf/
├── framework.sh          # Core loader, mbf::use (with MBF_EXT_PATH), strict, dry-run & version helpers
├── install.sh            # Idempotent one-command installer
├── bin/
│   └── mbf               # CLI entry point (init, list, new, doctor, export, compile, monitor, test, update, version)
├── lib/                  # 9 Core libraries + built-in .tpl templates
│   ├── log.sh
│   ├── args.sh
│   ├── exec.sh
│   ├── system.sh
│   ├── config.sh
│   ├── template.sh
│   ├── json.sh
│   ├── net.sh
│   ├── str.sh
│   └── templates/
├── plugins/              # 10 Opt-in operational plugins
│   ├── ai.sh
│   ├── monitor.sh
│   ├── notify.sh
│   ├── security.sh
│   ├── webserver.sh
│   ├── database.sh
│   ├── backup.sh
│   ├── cron.sh
│   ├── runtime.sh
│   └── obfuscator.sh
├── tools/                # Build & diagnostic tools (exporter.sh, doctor.sh, compiler.sh)
├── docs/                 # Comprehensive documentation
│   ├── LIBRARIES.md      # Core libraries overview & index
│   ├── PLUGINS.md        # Plugins overview & index
│   ├── EXTENDING.md      # Custom extension & template authoring guide
│   ├── libraries/        # Detailed function-by-function guides & examples for each library
│   ├── plugins/          # Detailed function-by-function guides & examples for each plugin
│   └── case-studies/     # Real-world architectural blueprints
└── test/                 # Subshell-isolated unit & plugin test suites (standard + strict mode)
```
