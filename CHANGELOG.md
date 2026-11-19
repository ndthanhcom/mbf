# Changelog

All notable changes to **MBF (Micro Bash Framework)** are documented in this file.

## [1.0.0] — 2026-11-19

First production release of MBF — a clean, modular, zero-bloat Bash 4+ framework for DevOps automation.

### Core Framework & Libraries (`framework.sh`, `lib/`)
- **`framework.sh`**: Zero-dependency module loader (`mbf::use`), `# mbf:requires` dependency resolution, `mbf::strict` (`set -Eeuo pipefail` + `ERR` trap, safe in exported scripts), `MBF_API_VERSION="1"`, `MBF_USER_PLUGINS_DIR` discovery, and XDG-cached monthly update checks (`~/.cache/mbf/version_check`).
- **`lib/log.sh`**: Structured logging to `stderr` by default (`MBF_LOG_STDERR=1`, opt-out via `0`), TTY auto-color detection, `MBF_LOG_FORMAT=json`, `MBF_LOG_CI=1` GitHub Actions annotations, `mbf::log::redact` secret masking, stack traces, and file sink.
- **`lib/args.sh`**: Declarative flags (with automatic `--no-<flag>` negation), key-value options, `mbf::args::require`, subcommand routing (`mbf::args::command` / `mbf::args::dispatch`), `--` handling, and auto-generated `--help`.
- **`lib/exec.sh`**: Safe array-based `mbf::exec::run` (dry-run aware), `sudo`, `as_user`, `retry` (with `MBF_RETRY_BACKOFF=exp`), portable `timeout`, CI-aware `confirm`, signal-safe `on_exit` (`EXIT`/`INT`/`TERM`), `tmpfile`/`tmpdir` (safely quoted), atomic `mkdir` locks (`BASHPID`), and dry-run-safe `step_run` checkpoints.
- **`lib/ssh.sh`**: Agentless SSH remote execution, `ControlMaster` multiplexing, `run`, `run_bash`, `exec_script` (with `--self-remove` `0700` remote staging), `upload`, `sync`, and sequential/parallel `run_many`.
- **`lib/config.sh`**: Literal `awk` KV/directive/block config mutations with `.mbf.bak` backup/rollback, safe `mbf::config::load_env` (no `source`/`eval`), and Docker/K8s `*_FILE` `mbf::config::read_secret` with automatic log redaction.
- **`lib/net.sh`**: HTTP/REST client with custom `MBF_HTTP_HEADERS`, atomic SHA-256 verified downloads, TCP port & HTTP readiness polling, and DNS/IP helpers.
- **`lib/system.sh`**: Cross-environment detection (`linux`, `macos`, `gitbash`, `wsl`, `termux`), unified package/service/user/SSH/sudoers helpers, and validators.
- **`lib/template.sh`**: 3-tier `.tpl` resolver, `# @mbf-vars:` validation, and Bash 5.2-safe `{{VAR}}` rendering.
- **`lib/json.sh`** & **`lib/str.sh`**: Zero-dependency JSON builder/extractor, string `trim`/`slugify`, cryptographic `random`, `sha256`, and `hmac_sha256`.

### Built-in Operational Plugins (`plugins/`)
- **`ai`**: AI CLI (`claude`, `agy`, `gemini`, `codex`, `hermes`, `ollama`, `llm`) & OpenAI-compatible HTTP API (`MBF_AI_BASE_URL`) integration with pre-send secret redaction, context size capping, `MBF_AI_TIMEOUT`, `ask_json`, and safe human-in-the-loop `mbf::ai::run`.
- **`deploy`**: Capistrano / Deployer.php-style atomic zero-downtime release engine (`setup`, `lock`, `prepare`, `fetch_git`, `upload_release`, `shared`, `writable`, atomic `symlink`, `releases`, `rollback`, `cleanup`).
- **`notify`**, **`cron`**, **`backup`**, **`monitor`**, **`security`**: Lean operational plugins for alerting, tagged crontabs, verified backups, server auditing, and comment-safe SSH/firewall hardening.

### CLI, Tooling & Distribution (`bin/mbf`, `tools/`, CI/CD)
- **CLI**: `mbf --init`, `list`, `plugin <list|add|remove>`, `new [--ext]`, `doctor`, `remote [--self-remove]`, `ai`, `export`, `monitor`, `test`, `update`, `--version`.
- **Smart Exporter (`tools/exporter.sh`)**: Single-pass POSIX `awk` tree-shaker with automatic built-in template bundling.
- **Diagnostics (`tools/doctor.sh`)**: Validates module headers, `# @mbf-api:` compatibility, `# mbf:requires`, templates, and export readiness.
- **Supply-Chain & CI/CD**: Pinned `install.sh --version <tag>`, automated GitHub Release workflow with `SHA256SUMS.txt` (`.github/workflows/release.yml`), reusable GitHub Action (`action.yml`), minimal Alpine `Dockerfile`, ShellCheck `-S warning`, 4-OS CI matrix (Ubuntu, macOS, Windows Git Bash, Alpine Bash 4.4), and Docker OpenSSH integration test.
