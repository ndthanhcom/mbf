# MBF Core Libraries Reference (`lib/`)

Core libraries provide the essential, zero-dependency building blocks for every `mbf` script. Load them on demand with `mbf::use <lib1> <lib2>`.

## Importance Ranking Legend
- **`••••` (Essential)**: Recommended for almost every script (`log`, `args`, `exec`).
- **`•••` (Foundation)**: Standard system, configuration, template, JSON, and network primitives (`system`, `config`, `template`, `json`, `net`).
- **`••` (Utility)**: Non-trivial string sanitization and cryptographic digests (`str`).

---

## 0. `framework.sh` — Core Loader & Predicates
Sourced at the top of every `mbf` script (`source "$(mbf --init)"`). Enforces Bash >= 4.0 and loads `log` by default.

### Functions
- `mbf::version` — Print the current `mbf` framework version (`MBF_VERSION`).
- `mbf::check_update [--force]` — Periodically check (once every 30 days, cached in `$MBF_HOME/.version_check`) whether a newer `mbf` version is available and suggest running `mbf update`. Automatically skipped in exported scripts, non-interactive shells, CI, or when `MBF_NO_UPDATE_CHECK=1`.
- `mbf::use <module...>` — Load one or more libraries, plugins, or custom extensions (resolves `# mbf:requires` headers).
- `mbf::is_loaded <module>` — Return `0` if `<module>` is already loaded.
- `mbf::init` — Optional explicit initialization (runs `mbf::exec::init_sudo` when `MBF_SUDO=1`).
- `mbf::strict` — Enable `set -Eeuo pipefail` with an `ERR` trap that logs failing file, line, command, and exit code.
- `mbf::is_dryrun` — Return `0` when `MBF_DRYRUN=1`.
- `mbf::in_list <needle> <item1> [item2...]` — Return `0` if `<needle>` matches any item.
- `mbf::update [branch]` — Update the `mbf` installation via `git pull --ff-only`.

---

## 1. `log` `[••••]` — Structured Logging & Diagnostics
Loaded automatically by `framework.sh`. Provides colorized terminal logging, stack traces, extension resolution tracing, and optional file logging.

### Output Stream Contract
- `mbf::log::info` and `mbf::log::ok` write to **stdout** by default (backward compatible) or to **stderr** when `MBF_LOG_STDERR=1` is set.
- `mbf::log::warn`, `mbf::log::error`, `mbf::log::debug`, and `mbf::log::debug_ext` always write to **stderr**.
- All messages are printed literally (`%s`), so backslashes (such as Windows paths) are never interpreted as escapes.

### Environment Variables
- `MBF_LOG=1` — Append all log messages to `MBF_LOG_FILE` (default: `/tmp/mbf.log`).
- `MBF_LOG_FILE` — Target log file path.
- `MBF_LOG_STDERR=1` — Route `info` and `ok` messages to `stderr` so `$(...)` command substitutions capture only data.
- `MBF_DEBUG=1` — Enable `mbf::log::debug`, stack traces on error, and error file logging.
- `MBF_DEBUG_EXT=1` — Enable `mbf::log::debug_ext` to trace custom extension and template resolution.
- `NO_COLOR=1` — Disable ANSI color codes.

### Functions
- `mbf::log::info <message>` — Log informational message.
- `mbf::log::ok <message>` — Log success message in green.
- `mbf::log::warn <message>` — Log warning message in yellow to stderr.
- `mbf::log::error <message>` — Log error message in red to stderr (prints stack trace if `MBF_DEBUG=1`).
- `mbf::log::debug <message>` — Log caller file, line number, function name, and message when `MBF_DEBUG=1`.
- `mbf::log::debug_ext <message>` — Log `[EXT-DEBUG]` trace when troubleshooting custom extensions/templates.
- `mbf::log::write_file <level> <message>` — Append a timestamped entry directly to `MBF_LOG_FILE`.
- `mbf::log::is_file_enabled` / `mbf::log::is_debug` / `mbf::log::is_debug_ext` — Logging state predicates.
- `mbf::log::stack_trace` — Print the current Bash function call stack.
- `mbf::log::xtrace_on` / `mbf::log::xtrace_off` — Enable/disable formatted `set -x` tracing.
- `mbf::die <message>` — Log fatal error and terminate script with exit code `1`.

---

## 2. `args` `[••••]` — Declarative CLI Arguments & Auto `--help`
Defines short/long flags and options declaratively, populates variables with defaults, collects positional arguments into `MBF_POSITIONAL_ARGS`, and auto-generates `-h | --help`.

### Functions
- `mbf::args::flag <short> <long> <VAR_NAME> <description>` — Register a boolean flag (`0` by default, `1` when passed).
- `mbf::args::option <short> <long> <VAR_NAME> <description> [default_value]` — Register a key-value option (supports `-e val`, `--env val`, and `--env=val`).
- `mbf::args::parse "$@"` — Parse CLI arguments (supports `--` end-of-options; exits `0` after printing `--help` unless `MBF_ARGS_NO_EXIT=1`).
- `mbf::args::help` — Print formatted usage and options table.

---

## 3. `exec` `[••••]` — Safe Execution, Retries, Traps, Temp Files & Locks
Executes commands safely as argument arrays (no `eval`), respects `MBF_DRYRUN=1` (`--dry-run`), manages cleanup traps and auto-deleted temporary files/directories, and provides process locks and idempotent step checkpointing.

### Functions
- `mbf::exec::init_sudo` — Pre-authenticate `sudo -v` session when non-root.
- `mbf::exec::run <cmd> [args...]` — Execute command safely; skips execution when `MBF_DRYRUN=1`.
- `mbf::exec::sudo <cmd> [args...]` — Execute command with `sudo` when non-root.
- `mbf::exec::as_user <username> <cmd> [args...]` — Execute command as `<username>`.
- `mbf::exec::retry <attempts> <delay_sec> <cmd> [args...]` — Retry command on failure.
- `mbf::exec::scripts_in_dir <dir> <interpreter> [ext]` — Run all `*.<ext>` scripts in `<dir>` in sorted order.
- `mbf::exec::on_exit "<cleanup_cmd>"` — Register a command to run on shell/subshell `EXIT` (chains multiple hooks in LIFO order).
- `mbf::exec::tmpfile <OUT_VAR>` — Create a temporary file, store its path in `<OUT_VAR>`, and auto-remove on exit.
- `mbf::exec::tmpdir <OUT_VAR>` — Create a temporary directory, store its path in `<OUT_VAR>`, and auto-remove on exit.
- `mbf::exec::lock_acquire <lock_name> [timeout_sec]` — Acquire a concurrency lock with stale-PID recovery.
- `mbf::exec::lock_release <lock_name>` — Release a concurrency lock.
- `mbf::exec::step_done <step_id>` / `mbf::exec::step_mark <step_id>` — Query or mark a step in `MBF_STATE_FILE`.
- `mbf::exec::step_run <step_id> <cmd> [args...]` — Run `<cmd>` only if `<step_id>` has not yet been recorded in `MBF_STATE_FILE`.

---

## 4. `system` `[•••]` — Cross-Environment OS, Packages, Services, Users & Checks
Provides a unified interface across **Linux**, **macOS**, **Windows Git Bash**, **WSL**, and **Android Termux**.

### Functions
- **Environment & OS**:
  - `mbf::system::env_type` — Returns `linux`, `macos`, `gitbash`, `wsl`, or `termux`.
  - `mbf::system::prefix` — Returns `$PREFIX` on Termux or empty string on standard systems.
  - `mbf::system::as_root <cmd> [args...]` — Runs directly on `EUID == 0`, Termux, or Git Bash, and uses `sudo` otherwise.
  - `mbf::system::distro` / `mbf::system::version` / `mbf::system::arch`
- **Packages**:
  - `mbf::system::pkg_manager` — Detects `pkg` (Termux), `apt-get`, `dnf`, `yum`, `apk`, `pacman`, `zypper`, `brew`, `winget`, or `choco`.
  - `mbf::system::pkg_update` / `mbf::system::pkg_install <pkg...>` / `mbf::system::pkg_is_installed <pkg>`
- **Services**:
  - `mbf::system::service <start|stop|restart|reload|enable> <name>`
  - `mbf::system::service_is_active <name>` / `mbf::system::service_ensure <name>`
- **Users & SSH**:
  - `mbf::system::user_exists <user>` / `mbf::system::user_ensure <user> [home] [shell]`
  - `mbf::system::ssh_key_add <user> "<pubkey>" [auth_file]` / `mbf::system::ssh_key_remove <user> <pattern> [auth_file]`
  - `mbf::system::sudo_nopasswd <user> [cmds] [sudoers_dir]`
- **Pre-flight & Input Validation**:
  - `mbf::system::check_cmd <cmd> [ver]` / `mbf::system::check_cmds <cmd1> <cmd2>...` / `mbf::system::check_env <VAR1>...`
  - `mbf::system::is_domain <str>` / `mbf::system::is_ip <str>` / `mbf::system::is_email <str>` / `mbf::system::is_alnum <str>`

---

## 5. `config` `[•••]` — Idempotent Config File Manipulation & Backup
Mutates `.env`, `.ini`, and `.conf` files safely using literal `awk` matching (no regex escaping bugs with `/`, `&`, `|`, or `\`) while preserving file permissions and symlinks.

### Functions
- `mbf::config::get <file> <key>` — Read value of `key = value` or `key=value` (exact key match).
- `mbf::config::set <file> <key> <value>` — Set or update `key = value` (exact key match; appends if missing).
- `mbf::config::get_directive <file> <Key>` — Read a space-separated directive (`Key value`, case-insensitive, first match wins).
- `mbf::config::insert <file> <line>` — Append line to file.
- `mbf::config::ensure <file> <line>` — Append line only if not already present.
- `mbf::config::ensure_block <file> <block_id> <multiline_content> [top]` — Idempotently insert or update a `# BEGIN MBF:<block_id> ... # END MBF:<block_id>` section in place.
- `mbf::config::delete_line <file> <pattern>` — Remove lines containing `<pattern>`.
- `mbf::config::replace_line <file> <pattern> <new_line>` — Replace matching lines.
- `mbf::config::replace_text <file> <search> <replacement>` — Replace literal substring across file.
- `mbf::config::line_number <file> <text>` / `mbf::config::append_after_line <file> <line_no> <text>`
- `mbf::config::backup <file>` / `mbf::config::rollback <file>` — Save and restore `.mbf.bak` backups.

---

## 6. `template` `[•••]` — Template Resolution & `{{VAR}}` Rendering
Renders `.tpl` configuration templates with automatic variable validation and a 3-tier lookup hierarchy so scripts can override built-in templates or bundle their own.

### Functions
- `mbf::template::resolve <name_or_path>` — Print resolved path to template file.
- `mbf::template::validate_vars <tpl_file> [KEY=val...]` — Verify all variables declared in `# @mbf-vars: VAR1 VAR2` are set.
- `mbf::template::render <tpl_name_or_path> <dest_file> [KEY=val...]` — Validate, render `{{VAR}}` placeholders, and write atomically.
- `mbf::template::render_str "<string>" [KEY=val...]` — Render `{{VAR}}` placeholders in memory (safe with `&` and `\` in values).
- `mbf::template::write_atomic <dest_file>` — Write stdin to `<dest_file>` atomically while preserving existing permissions.
- `mbf::template::list` — List all discoverable `.tpl` templates.

---

## 7. `json` `[•••]` — Zero-Dependency JSON Builder & Parser
Constructs and queries JSON payloads for webhooks, APIs, and agent telemetry without requiring `jq` or Python.

### Functions
- `mbf::json::escape <string>` — Escape quotes, backslashes, and control characters.
- `mbf::json::object "key=str" "num:=42" "flag:=true"` — Build a JSON object (`=` quotes strings; `:=` at the end of `<key>` emits raw numbers/booleans).
- `mbf::json::array "item1" "item2"` — Build a JSON string array.
- `mbf::json::get <json_string> <key>` — Extract scalar value for `<key>` (unescapes `\"`, `\\`, `\n`, `\t`, `\/`).

---

## 8. `net` `[•••]` — HTTP Client, Checksum Downloads, Ports & DNS
Wraps `curl`/`wget` and socket tools with dry-run awareness, atomic downloads, and readiness polling.

### Functions
- `mbf::net::request <METHOD> <url> [body] [content_type]` — Perform HTTP request (`curl` or `wget --method`).
- `mbf::net::post_json <url> <json_body>` — POST JSON payload.
- `mbf::net::status_code <url> [timeout]` — Return HTTP status code (`200`, `404`, `502`).
- `mbf::net::wait_http <url> [timeout_sec] [expected_code]` — Poll URL until it returns expected HTTP status.
- `mbf::net::download <url> <dest_file> [expected_sha256]` — Download file atomically via temp file and optionally verify SHA-256 checksum.
- `mbf::net::private_ip` / `mbf::net::public_ip` — Detect local and public IPv4 addresses.
- `mbf::net::is_port_open <port> [host]` / `mbf::net::wait_port <port> [host] [timeout_sec]` — Check or poll TCP port.
- `mbf::net::resolve_dns <domain>` — Resolve domain to IPv4 address.

---

## 9. `str` `[••]` — String Sanitization, Random Tokens & Cryptographic Hashes
Contains only non-trivial string and digest operations (for lowercase/uppercase, use native Bash `${var,,}` and `${var^^}`).

### Functions
- `mbf::str::trim <string>` — Strip leading and trailing whitespace.
- `mbf::str::slugify <string>` — Convert text into lowercase URL/filename slug (`my-site-01`).
- `mbf::str::random [length]` — Generate cryptographically random alphanumeric token (default: `24` chars; `pipefail`-safe).
- `mbf::str::sha256 <file>` — Compute SHA-256 hex digest of a file.
- `mbf::str::verify_sha256 <file> <expected_hex>` — Verify file checksum matches `<expected_hex>`.
- `mbf::str::hmac_sha256 <secret> <payload>` — Compute HMAC-SHA256 signature.
