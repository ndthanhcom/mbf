# MBF Core Libraries Reference (`lib/`)

Core libraries provide the essential, zero-dependency building blocks for every `mbf` script. Load them on demand with `mbf::use <lib1> <lib2>`.

Each section below summarizes the library's functions, provides a quick example, and links to its **detailed function-by-function guide** in [`docs/libraries/`](libraries/).

---

## 0. `framework.sh` — Core Loader & Predicates
**Detailed Guide & Function Examples**: [`docs/libraries/framework.md`](libraries/framework.md)

Sourced at the top of every `mbf` script (`source "$(mbf --init)"`). Enforces Bash >= 4.0, loads `log` by default, and runs a non-blocking monthly version check (`~/.cache/mbf/version_check`) in interactive shells.

### Functions
- `mbf::version` — Print the current `mbf` framework version (`MBF_VERSION`).
- `mbf::check_update [--force]` — Check once every 30 days whether a newer `mbf` version is available and suggest running `mbf version update`.
- `mbf::use <module...>` — Load one or more libraries, plugins, or custom extensions (resolves `# mbf:requires` headers).
- `mbf::is_loaded <module>` — Return `0` if `<module>` is already loaded.
- `mbf::init` — Optional explicit initialization (runs `mbf::exec::init_sudo` when `MBF_SUDO=1`).
- `mbf::strict` — Enable `set -Eeuo pipefail` with an `ERR` trap that logs failing file, line, command, and exit code.
- `mbf::is_dryrun` — Return `0` when `MBF_DRYRUN=1`.
- `mbf::in_list <needle> <item1> [item2...]` — Return `0` if `<needle>` matches any item.
- `mbf::update [branch]` — Update the `mbf` installation via `git pull --ff-only` (`mbf version update`).
- `mbf::list_versions` — List available Git version tags in `$MBF_HOME` (`mbf version list`).
- `mbf::switch_version <tag_or_branch> [--force]` — Switch local `$MBF_HOME` to a specific Git tag or branch (`mbf version change <tag>`).

```bash
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::strict
mbf::use log args exec config
```

---

## 1. `log` — Structured Logging & Diagnostics
**Detailed Guide & Function Examples**: [`docs/libraries/log.md`](libraries/log.md)

Loaded automatically by `framework.sh`. Provides colorized ISO-8601 terminal logging, stack traces, extension resolution tracing, and optional file logging.

### Functions
- `mbf::log::info <message>` — Log informational message (stderr by default; stdout if `MBF_LOG_STDERR=0`).
- `mbf::log::ok <message>` — Log success message in green.
- `mbf::log::warn <message>` — Log warning message in yellow to stderr.
- `mbf::log::error <message>` — Log error message in red to stderr (prints stack trace if `MBF_DEBUG=1`).
- `mbf::log::debug <message>` — Log caller `file:line:func` and message when `MBF_DEBUG=1`.
- `mbf::log::debug_ext <message>` — Log `[EXT-DEBUG]` trace when `MBF_DEBUG_EXT=1`.
- `mbf::log::write_file <level> <message>` — Append a timestamped entry directly to `MBF_LOG_FILE`.
- `mbf::log::is_file_enabled` / `mbf::log::is_debug` / `mbf::log::is_debug_ext` — Logging state predicates.
- `mbf::log::stack_trace` — Print the current Bash function call stack.
- `mbf::log::xtrace_on` / `mbf::log::xtrace_off` — Enable/disable formatted `set -x` tracing.
- `mbf::log::redact <secret...>` — Mask sensitive tokens/passwords as `***` across all log sinks (`MBF_LOG_FORMAT=json` and `MBF_LOG_CI=1` supported).
- `mbf::die <message>` — Log fatal error and terminate script with exit code `1`.

```bash
mbf::log::info "Reloading Nginx..."
mbf::log::ok   "Nginx reloaded successfully"
[ -f "/etc/nginx/nginx.conf" ] || mbf::die "Missing /etc/nginx/nginx.conf"
```

---

## 2. `args` — Declarative CLI Arguments & Auto `--help`
**Detailed Guide & Function Examples**: [`docs/libraries/args.md`](libraries/args.md)

Defines short/long flags and options declaratively, populates variables with defaults, collects positional arguments into `MBF_POSITIONAL_ARGS`, and auto-generates `-h | --help`.

### Functions
- `mbf::args::flag <short> <long> <VAR_NAME> <description>` — Register a boolean flag (`0` by default, `1` when passed; supports `--no-<long>` negation).
- `mbf::args::option <short> <long> <VAR_NAME> <description> [default_value]` — Register a key-value option (supports `-e val`, `--env val`, and `--env=val`).
- `mbf::args::require <VAR_NAME> [label]` — Assert a required option variable is non-empty.
- `mbf::args::command <name> <description>` / `mbf::args::dispatch <fn_prefix> "$@"` — Register and route CLI subcommands.
- `mbf::args::parse "$@"` — Parse CLI arguments (supports `--` end-of-options; exits `0` after printing `--help`).
- `mbf::args::help` — Print formatted usage, commands, and options table.

```bash
mbf::use args
USAGE="Usage: deploy.sh [options] <release_tag>"
mbf::args::flag   "n" "dry-run" "MBF_DRYRUN" "Preview changes without modifying files"
mbf::args::option "e" "env"     "OPT_ENV"    "Target environment" "production"
mbf::args::parse "$@" || exit 1
```

---

## 3. `exec` — Safe Execution, Retries, Traps, Temp Files & Locks
**Detailed Guide & Function Examples**: [`docs/libraries/exec.md`](libraries/exec.md)

Executes commands safely as argument arrays (no `eval`), respects `MBF_DRYRUN=1`, manages LIFO cleanup traps and auto-deleted temporary files/directories, and provides process locks and idempotent step checkpointing.

### Functions
- `mbf::exec::init_sudo` — Pre-authenticate `sudo -v` session when non-root.
- `mbf::exec::run <cmd> [args...]` — Execute command safely; skips execution when `MBF_DRYRUN=1`.
- `mbf::exec::sudo <cmd> [args...]` — Execute command with `sudo` when non-root.
- `mbf::exec::as_user <username> <cmd> [args...]` — Execute command as `<username>`.
- `mbf::exec::retry <attempts> <delay_sec> <cmd> [args...]` — Retry command on failure (supports `MBF_RETRY_BACKOFF=exp`).
- `mbf::exec::timeout <seconds> <cmd> [args...]` — Portable command timeout (returns `124` on timeout).
- `mbf::exec::confirm "<prompt>" [default:n|y]` — CI-aware interactive confirmation (`MBF_YES=1` auto-accepts).
- `mbf::exec::scripts_in_dir <dir> <interpreter> [ext]` — Run all `*.<ext>` scripts in `<dir>` in sorted order.
- `mbf::exec::on_exit "<cleanup_cmd>"` — Register a command to run on `EXIT`/`INT`/`TERM` (LIFO order).
- `mbf::exec::tmpfile <OUT_VAR>` / `mbf::exec::tmpdir <OUT_VAR>` — Create auto-deleted temporary file or directory.
- `mbf::exec::lock_acquire <lock_name> [timeout_sec]` / `mbf::exec::lock_release <lock_name>` — Concurrency lock with stale-PID recovery.
- `mbf::exec::step_done <step_id>` / `mbf::exec::step_mark <step_id>` / `mbf::exec::step_run <step_id> <cmd> [args...]` — Idempotent step checkpointing.

```bash
mbf::use exec
mbf::exec::lock_acquire "deploy_lock" 10 || exit 1
mbf::exec::tmpfile work_file
mbf::exec::retry 3 2 curl -fsSL https://example.com/health -o "$work_file"
mbf::exec::step_run "01_reload_nginx" mbf::exec::sudo systemctl reload nginx
```

---

## 4. `system` — Cross-Environment OS, Packages, Services, Users & Checks
**Detailed Guide & Function Examples**: [`docs/libraries/system.md`](libraries/system.md)

Provides a unified interface across **Linux**, **macOS**, **Windows Git Bash**, **WSL**, and **Android Termux**.

### Functions
- **Environment & OS**: `mbf::system::env_type`, `mbf::system::prefix`, `mbf::system::as_root <cmd> [args...]`, `mbf::system::distro`, `mbf::system::version`, `mbf::system::arch`
- **Packages**: `mbf::system::pkg_manager`, `mbf::system::pkg_update`, `mbf::system::pkg_install <pkg...>`, `mbf::system::pkg_is_installed <pkg>`
- **Services**: `mbf::system::service <start|stop|restart|reload|enable> <name>`, `mbf::system::service_is_active <name>`, `mbf::system::service_ensure <name>`
- **Users & SSH**: `mbf::system::user_exists <user>`, `mbf::system::user_ensure <user> [home] [shell]`, `mbf::system::ssh_key_add <user> "<pubkey>" [auth_file]`, `mbf::system::ssh_key_remove <user> <pattern> [auth_file]`, `mbf::system::sudo_nopasswd <user> [cmds] [sudoers_dir]`
- **Pre-flight & Input Validation**: `mbf::system::check_cmd <cmd> [ver]`, `mbf::system::check_cmds <cmd1>...`, `mbf::system::check_env <VAR1>...`, `mbf::system::is_domain <str>`, `mbf::system::is_ip <str>`, `mbf::system::is_email <str>`, `mbf::system::is_alnum <str>`

```bash
mbf::use system
mbf::system::check_cmds git curl || exit 1
mbf::system::pkg_install jq
mbf::system::service_ensure nginx
```

---

## 5. `config` — Idempotent Config File Manipulation & Backup
**Detailed Guide & Function Examples**: [`docs/libraries/config.md`](libraries/config.md)

Mutates `.env`, `.ini`, and `.conf` files safely using literal `awk` matching while preserving file permissions and symlinks.

### Functions
- `mbf::config::get <file> <key>` / `mbf::config::set <file> <key> <value>` — Exact key-value read and update.
- `mbf::config::get_directive <file> <Key>` — Space-separated directive reader (first match wins, case-insensitive).
- `mbf::config::insert <file> <line>` / `mbf::config::ensure <file> <line>` — Append or idempotently ensure a line.
- `mbf::config::ensure_block <file> <block_id> <multiline_content> [top]` — Manage `# BEGIN MBF:<block_id> ... # END MBF:<block_id>` section in place.
- `mbf::config::delete_line <file> <pattern>` / `mbf::config::replace_line <file> <pattern> <new_line>` / `mbf::config::replace_text <file> <search> <replacement>`
- `mbf::config::line_number <file> <text>` / `mbf::config::append_after_line <file> <line_no> <text>`
- `mbf::config::backup <file>` / `mbf::config::rollback <file>` — Save and restore `.mbf.bak` backups.
- `mbf::config::load_env <env_file> [override:0|1]` — Safe `.env` loader without `source` or `eval`.
- `mbf::config::read_secret <VAR_NAME> [fallback_file]` — Docker/K8s `*_FILE` secret reader with automatic `mbf::log::redact`.

```bash
mbf::use config
mbf::config::backup "/etc/php/8.2/fpm/php.ini"
mbf::config::set "/etc/php/8.2/fpm/php.ini" "memory_limit" "2G"
mbf::config::ensure "/etc/hosts" "127.0.0.1 app.local"
```

---

## 6. `template` — Template Resolution & `{{VAR}}` Rendering
**Detailed Guide & Function Examples**: [`docs/libraries/template.md`](libraries/template.md)

Renders `.tpl` configuration templates with `# @mbf-vars:` validation and a 3-tier lookup hierarchy (`./path` -> `MBF_TEMPLATE_PATH` / `./templates/` -> `$MBF_HOME/lib/templates/`).

### Functions
- `mbf::template::resolve <name_or_path>` — Print resolved path to template file.
- `mbf::template::validate_vars <tpl_file> [KEY=val...]` — Verify all `# @mbf-vars:` variables are provided.
- `mbf::template::render <tpl_name_or_path> <dest_file> [KEY=val...]` — Validate, render `{{VAR}}` placeholders, and write atomically.
- `mbf::template::render_str "<string>" [KEY=val...]` — Render `{{VAR}}` placeholders in memory.
- `mbf::template::write_atomic <dest_file>` — Write stdin to `<dest_file>` atomically.
- `mbf::template::list` — List all discoverable `.tpl` templates.

```bash
mbf::use template
# Resolves `./templates/app/service.conf.tpl` or `$MBF_TEMPLATE_PATH/...`
mbf::template::render "app/service.conf.tpl" "/etc/nginx/conf.d/shop.conf" \
    "DOMAIN=shop.example.com" \
    "ROOT_DIR=/var/www/shop/pub"
```

---

## 7. `json` — Zero-Dependency JSON Builder & Parser
**Detailed Guide & Function Examples**: [`docs/libraries/json.md`](libraries/json.md)

Constructs and queries JSON payloads without requiring `jq` or Python.

### Functions
- `mbf::json::escape <string>` — Escape quotes, backslashes, and control characters.
- `mbf::json::object "key=str" "num:=42" "flag:=true"` — Build a JSON object (`=` quotes strings; `:=` emits raw numbers/booleans).
- `mbf::json::array "item1" "item2"` — Build a JSON string array.
- `mbf::json::get <json_string> <key>` — Extract scalar value for `<key>`.

```bash
mbf::use json
payload="$(mbf::json::object "host=web01" "workers:=4" "ok:=true")"
status="$(mbf::json::get "$payload" "host")"
```

---

## 8. `net` — HTTP Client, Checksum Downloads, Ports & DNS
**Detailed Guide & Function Examples**: [`docs/libraries/net.md`](libraries/net.md)

Wraps `curl`/`wget` and socket tools with dry-run awareness, atomic downloads, and readiness polling.

### Functions
- `mbf::net::header_add "<Header: Value>"` / `mbf::net::headers_clear` — Manage custom HTTP headers (`MBF_HTTP_HEADERS`).
- `mbf::net::request <METHOD> <url> [body] [content_type]` / `mbf::net::post_json <url> <json_body>`
- `mbf::net::status_code <url> [timeout]` / `mbf::net::wait_http <url> [timeout_sec] [expected_code]`
- `mbf::net::download <url> <dest_file> [expected_sha256]` — Atomic download with SHA-256 verification.
- `mbf::net::private_ip` / `mbf::net::public_ip` / `mbf::net::resolve_dns <domain>`
- `mbf::net::is_port_open <port> [host]` / `mbf::net::wait_port <port> [host] [timeout_sec]`

```bash
mbf::use net
mbf::net::wait_port 3306 "127.0.0.1" 30
mbf::net::wait_http "https://shop.example.com/health" 30 200
```

---

## 9. `ssh` — Agentless SSH Remote Execution & Sync
**Detailed Guide & Function Examples**: [`docs/libraries/ssh.md`](libraries/ssh.md)

Executes commands and tree-shaken local MBF scripts agentlessly on remote servers over SSH, with `ControlMaster` multiplexing, `scp`/`rsync` transfers, and multi-host execution.

### Functions
- `mbf::ssh::check [host]` / `mbf::ssh::prompt [--verify]` — Pre-flight SSH connectivity check and CI-safe interactive prompt for missing host/user/port/key/password (`MBF_SSH_HOST`, `MBF_SSH_USER`, `MBF_SSH_PASSWORD`).
- `mbf::ssh::open [host]` / `mbf::ssh::close [host]` — Open/close persistent multiplexed SSH connection (auto-closed on exit).
- `mbf::ssh::run <host> <cmd> [args...]` — Execute safely quoted command on `<host>`.
- `mbf::ssh::run_bash <host> "<bash_code>" [args...]` — Stream multi-line Bash code over stdin to `<host>`.
- `mbf::ssh::exec_script [--self-remove] <host> <local_script.sh> [args...]` — Export local MBF script into a standalone script and execute it remotely with zero remote `mbf` installation (`--self-remove` stages as a `0700` self-deleting temp file).
- `mbf::ssh::upload <host> <local_path> <remote_path>` / `mbf::ssh::download [-r] <host> <remote_path> <local_path>` / `mbf::ssh::sync <host> <local_dir> <remote_dir> [rsync_args...]` — File upload, download, and `rsync` directory synchronization.
- `mbf::ssh::run_many <hosts_csv> <cmd> [args...]` — Execute command across multiple hosts (sequential or parallel via `MBF_SSH_PARALLEL=1`).

```bash
mbf::use ssh
mbf::ssh::open "deploy@web-01.example.com"
mbf::ssh::exec_script "deploy@web-01.example.com" "./scripts/healthcheck.sh" --port 8080
```

---

## 10. `str` — String Sanitization, Random Tokens & Cryptographic Hashes
**Detailed Guide & Function Examples**: [`docs/libraries/str.md`](libraries/str.md)

Contains non-trivial string and digest operations (for lowercase/uppercase, use native Bash `${var,,}` and `${var^^}`).

### Functions
- `mbf::str::trim <string>` — Strip leading and trailing whitespace.
- `mbf::str::slugify <string>` — Convert text into lowercase URL/filename slug (`my-site-01`).
- `mbf::str::random [length]` — Generate cryptographically random alphanumeric token (default: `24` chars).
- `mbf::str::sha256 <file>` / `mbf::str::verify_sha256 <file> <expected_hex>` — Compute or verify SHA-256 file digest.
- `mbf::str::hmac_sha256 <secret> <payload>` — Compute HMAC-SHA256 signature.

```bash
mbf::use str
slug="$(mbf::str::slugify "Store #1 (Prod)")"
token="$(mbf::str::random 32)"
```
