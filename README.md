# MBF — Micro Bash Framework

> **A clean, modular, zero-bloat Bash framework that is easy to learn, easy to use, and easy to understand.**

`mbf` turns fragile, copy-pasted shell scripts into structured, maintainable, and distributable automation—without adding runtime dependencies or hiding native Bash behind heavy abstractions.

---

## Why MBF?

1. **Zero Bloat, Native First**: If native Bash 4.3+ already does something in one expression, `mbf` stays out of your way. Every function in `mbf` solves a real operational problem.
2. **Tree-Shaken Standalone Export (`mbf export`)**: Write modular code using `mbf::use`, then compile your script into a **single zero-dependency `.sh` file** (or full app bundle) containing *only* the functions your script actually calls.
3. **Production Safety by Default**: Built-in `--dry-run` simulation (`MBF_DRYRUN=1`), declarative CLI flags with automatic `--help`, non-overlapping concurrency locks, idempotent config edits, and automatic backup/rollback.
4. **Write Once, Run Anywhere**: Unified environment, privilege, path prefix, and package manager abstractions across **Linux**, **macOS**, **Windows Git Bash**, **WSL**, and **Android Termux**.
5. **AI & Polyglot Ready**: Native integration with mainstream AI CLI tools (`claude`, `agy`, `gemini`, `codex`) for intelligent log/server analysis, plus seamless Node.js and Python execution and bundling.
6. **Infinitely Extensible**: Drop custom project libraries (`lib/`), plugins (`plugins/`), and `.tpl` templates (`templates/`) right next to your script—verified by `mbf doctor` and runtime `[EXT-DEBUG]` tracing.

---

## 60-Second Quick Start

### 1. Install
```bash
git clone https://github.com/ndthanhcom/mbf.git ~/.mbf
~/.mbf/install.sh
```

### 2. Create a Script (`mbf new deploy.sh`)
```bash
#!/usr/bin/env bash
source "$(mbf --init)"
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
# Preview safely in dry-run mode
./deploy.sh --dry-run --domain shop.example.com

# Export a tree-shaken, zero-dependency standalone script for any target server
mbf export deploy.sh -o dist/deploy.sh
```

---

## Module Overview & Importance Ranking

Modules are ranked from **`••••` (Essential)** to **`•` (Specialized)** to guide inclusion when authoring scripts:

### Core Libraries (`lib/`) — [Full Reference (`docs/LIBRARIES.md`)](docs/LIBRARIES.md)
| Library | Rank | Purpose |
| :--- | :--- | :--- |
| **`log`** | `••••` | Structured terminal logging, file logging, stack traces & `[EXT-DEBUG]` diagnostics |
| **`args`** | `••••` | Declarative CLI flags, options, defaults & automatic `--help` generation |
| **`exec`** | `••••` | Dry-run command runner, retries, `EXIT` traps, auto-cleaned temp files & locks |
| **`system`** | `•••` | Cross-env detection (`linux`/`macos`/`gitbash`/`wsl`/`termux`), packages, services & checks |
| **`config`** | `•••` | Idempotent KV, line, and multi-line block config mutations + `.mbf.bak` rollback |
| **`template`** | `•••` | Convention-based `.tpl` resolver (user override + built-in) & `{{VAR}}` atomic renderer |
| **`json`** | `•••` | Zero-dependency JSON escaping, object/array builder & key extractor |
| **`net`** | `•••` | HTTP/REST client, SHA-256 verified downloads, TCP port polling & DNS/IP lookup |
| **`str`** | `••` | String `trim`, `slugify`, cryptographic `random`, `sha256` & `hmac_sha256` |

### Plugins (`plugins/`) — [Full Reference (`docs/PLUGINS.md`)](docs/PLUGINS.md)
| Plugin | Rank | Purpose |
| :--- | :--- | :--- |
| **`ai`** | `•••` | Mainstream AI CLI integration (`claude`, `agy`, `gemini`, `codex` + fallbacks) |
| **`monitor`** | `•••` | Server resource/performance/log audits, SaaS webhook telemetry & Slack/TG/Email alerts |
| **`security`** | `•••` | SSH & system security auditing, automated SSH hardening & UFW/firewalld management |
| **`webserver`** | `••` | Template-driven Nginx vhosts, Let's Encrypt/self-signed SSL & PHP/WordPress stacks |
| **`database`** | `••` | MySQL/PostgreSQL/Redis provisioning, SQL dump/restore & rotating directory backups |
| **`cron`** | `••` | Tagged idempotent crontab management (`# mbf:id=`) & non-overlapping guarded execution |
| **`runtime`** | `•` | Polyglot Node.js, Python & external binary runner and bundle packager |
| **`obfuscator`** | `•` | Bash script obfuscation add-on (`bash-obfuscate` wrapper) |

---

## Documentation & Case Studies

- **[Core Libraries Reference (`docs/LIBRARIES.md`)](docs/LIBRARIES.md)** — Detailed API and examples for all 9 core libraries.
- **[Plugins Reference (`docs/PLUGINS.md`)](docs/PLUGINS.md)** — Detailed API and examples for all 8 plugins.
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
mbf export <script.sh> [-o <out>] [-d <dir>]  Export tree-shaken standalone script or app bundle
mbf compile <script.sh> [-o <bin>]            Compile exported script into a binary via shc
mbf monitor [check]                           Run server monitoring report (all, resources, logs, etc.)
mbf update [branch]                           Update mbf via git pull
mbf test [filter]                             Run the automated test suite
```

---

## Repository Structure

```text
mbf/
├── framework.sh          # Core loader, mbf::use (with MBF_EXT_PATH), strict & dry-run helpers
├── install.sh            # Idempotent one-command installer
├── bin/
│   └── mbf               # CLI entry point (init, list, new, doctor, export, compile, monitor, test, update)
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
├── plugins/              # 8 Opt-in operational plugins
│   ├── ai.sh
│   ├── monitor.sh
│   ├── security.sh
│   ├── webserver.sh
│   ├── database.sh
│   ├── cron.sh
│   ├── runtime.sh
│   └── obfuscator.sh
├── tools/                # Build & diagnostic tools (exporter.sh, doctor.sh, compiler.sh)
├── docs/                 # Library/plugin references, extension guide & real-world case studies
└── test/                 # Subshell-isolated unit & plugin test suites
```
