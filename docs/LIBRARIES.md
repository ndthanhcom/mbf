# MBF Core Libraries Reference (`lib/`)

Core libraries provide the essential, zero-dependency building blocks for every `mbf` script. Load them on demand with `mbf::use <lib1> <lib2>`.

## Importance Ranking Legend
- **`••••` (Essential)**: Recommended for almost every script (`log`, `args`, `exec`).
- **`•••` (Foundation)**: Standard system, configuration, template, JSON, and network primitives (`system`, `config`, `template`, `json`, `net`).
- **`••` (Utility)**: Non-trivial string sanitization and cryptographic digests (`str`).

---

## 1. `log` `[••••]` — Structured Logging & Diagnostics
Loaded automatically by `framework.sh`. Provides colorized terminal logging, stack traces, extension resolution tracing, and optional file logging.

### Environment Variables
- `MBF_LOG=1` — Append all log messages to `MBF_LOG_FILE` (default: `/tmp/mbf.log`).
- `MBF_DEBUG=1` — Enable `mbf::log::debug`, stack traces on error, and error file logging.
- `MBF_DEBUG_EXT=1` — Enable `mbf::log::debug_ext` to trace custom extension and template resolution.
- `NO_COLOR=1` — Disable ANSI color codes.

### Functions
- `mbf::log::info <message>` — Log informational message to stdout.
- `mbf::log::ok <message>` — Log success message in green to stdout.
- `mbf::log::warn <message>` — Log warning message in yellow to stderr.
- `mbf::log::error <message>` — Log error message in red to stderr (prints stack trace if `MBF_DEBUG=1`).
- `mbf::log::debug <message>` — Log caller file, line number, function name, and message when `MBF_DEBUG=1`.
- `mbf::log::debug_ext <message>` — Log `[EXT-DEBUG]` trace when troubleshooting custom extensions/templates.
- `mbf::log::stack_trace` — Print the current Bash function call stack.
- `mbf::log::xtrace_on` / `mbf::log::xtrace_off` — Enable/disable formatted `set -x` tracing.
- `mbf::die <message>` — Log fatal error and terminate script with exit code `1`.

---

## 2. `args` `[••••]` — Declarative CLI Arguments & Auto `--help`
Defines short/long flags and options declaratively, populates variables with defaults, collects positional arguments into `MBF_POSITIONAL_ARGS`, and auto-generates `-h | --help`.

### Functions
- `mbf::args::flag <short> <long> <VAR_NAME> <description>` — Register a boolean flag (`0` by default, `1` when passed).
- `mbf::args::option <short> <long> <VAR_NAME> <description> [default_value]` — Register a key-value option (supports `-e val`, `--env val`, and `--env=val`).
- `mbf::args::parse "$@"` — Parse CLI arguments.
- `mbf::args::help` — Print formatted usage and options table.

### Example
```bash
mbf::use args
USAGE="Usage: deploy.sh [options] <release_tag>"
mbf::args::flag   "v" "verbose" "MBF_DEBUG" "Enable debug output"
mbf::args::option "e" "env"     "OPT_ENV"   "Target environment" "production"
mbf::args::parse "$@" || exit 1
```

---

## 3. `exec` `[••••]` — Safe Execution, Retries, Traps, Temp Files & Locks
Executes commands safely as argument arrays (no `eval`), respects `MBF_DRYRUN=1` (`--dry-run`), manages cleanup traps and auto-deleted temporary files/directories, and provides process locks and idempotent step checkpointing.

### Functions
- `mbf::exec::run <cmd> [args...]` — Execute command safely; skips execution when `MBF_DRYRUN=1`.
- `mbf::exec::sudo <cmd> [args...]` — Execute command with `sudo` when non-root.
- `mbf::exec::as_user <username> <cmd> [args...]` — Execute command as `<username>`.
- `mbf::exec::retry <attempts> <delay_sec> <cmd> [args...]` — Retry command on failure.
- `mbf::exec::scripts_in_dir <dir> <interpreter> [ext]` — Run all `*.<ext>` scripts in `<dir>` in sorted order.
- `mbf::exec::on_exit "<cleanup_cmd>"` — Register a command to run on shell `EXIT` (chains multiple hooks in LIFO order).
- `mbf::exec::tmpfile <OUT_VAR>` — Create a temporary file, store its path in `<OUT_VAR>`, and auto-remove on exit.
- `mbf::exec::tmpdir <OUT_VAR>` — Create a temporary directory, store its path in `<OUT_VAR>`, and auto-remove on exit.
- `mbf::exec::lock_acquire <lock_name> [timeout_sec]` — Acquire a concurrency lock with stale-PID recovery.
- `mbf::exec::lock_release <lock_name>` — Release a concurrency lock.
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
Mutates `.env`, `.ini`, and `.conf` files safely without `eval`, including multi-line managed blocks and rollback backups.

### Functions
- `mbf::config::get <file> <key>` — Read value of `key = value` or `key=value`.
- `mbf::config::set <file> <key> <value>` — Set or update `key = value` (appends if key is missing).
- `mbf::config::insert <file> <line>` — Append line to file.
- `mbf::config::ensure <file> <line>` — Append line only if not already present.
- `mbf::config::ensure_block <file> <block_id> <multiline_content>` — Idempotently insert or update a `# BEGIN MBF:<block_id> ... # END MBF:<block_id>` section.
- `mbf::config::delete_line <file> <pattern>` — Remove lines matching `<pattern>`.
- `mbf::config::replace_line <file> <pattern> <new_line>` — Replace matching lines.
- `mbf::config::replace_text <file> <search> <replacement>` — Replace substring across file (safe with `/` paths).
- `mbf::config::line_number <file> <text>` / `mbf::config::append_after_line <file> <line_no> <text>`
- `mbf::config::backup <file>` / `mbf::config::rollback <file>` — Save and restore `.mbf.bak` backups.

---

## 6. `template` `[•••]` — Template Resolution & `{{VAR}}` Rendering
Renders `.tpl` configuration templates with automatic variable validation and a 3-tier lookup hierarchy so scripts can override built-in templates or bundle their own.

### Lookup Order (`mbf::template::resolve <name>`)
1. Explicit file path (`./my.conf.tpl`)
2. Custom directories in `MBF_TEMPLATE_PATH` and `<script_dir>/templates/<name>[.tpl]`
3. Built-in `$MBF_HOME/lib/templates/<name>[.tpl]` (`nginx/vhost-static.conf.tpl`, `nginx/vhost-php.conf.tpl`, `nginx/vhost-proxy.conf.tpl`, `script/extension.sh.tpl`)

### Functions
- `mbf::template::resolve <name_or_path>` — Print resolved path to template file.
- `mbf::template::validate_vars <tpl_file> [KEY=val...]` — Verify all variables declared in `# @mbf-vars: VAR1 VAR2` are set.
- `mbf::template::render <tpl_name_or_path> <dest_file> [KEY=val...]` — Validate, render `{{VAR}}` placeholders, and write atomically.
- `mbf::template::render_str "<string>" [KEY=val...]` — Render `{{VAR}}` placeholders in memory.
- `mbf::template::write_atomic <dest_file>` — Write stdin to `<dest_file>` via atomic temp file rename.
- `mbf::template::list` — List all discoverable `.tpl` templates.

---

## 7. `json` `[•••]` — Zero-Dependency JSON Builder & Parser
Constructs and queries JSON payloads for webhooks, APIs, and agent telemetry without requiring `jq` or Python.

### Functions
- `mbf::json::escape <string>` — Escape quotes, backslashes, and control characters.
- `mbf::json::object "key=str" "num:=42" "flag:=true"` — Build a JSON object (`=` quotes strings; `:=` emits raw numbers/booleans).
- `mbf::json::array "item1" "item2"` — Build a JSON string array.
- `mbf::json::get <json_string> <key>` — Extract top-level scalar value for `<key>`.

---

## 8. `net` `[•••]` — HTTP Client, Checksum Downloads, Ports & DNS
Wraps `curl`/`wget` and socket tools with dry-run awareness and readiness polling.

### Functions
- `mbf::net::request <METHOD> <url> [body] [content_type]` — Perform HTTP request.
- `mbf::net::post_json <url> <json_body>` — POST JSON payload.
- `mbf::net::status_code <url> [timeout]` — Return HTTP status code (`200`, `404`, `502`).
- `mbf::net::wait_http <url> [timeout_sec] [expected_code]` — Poll URL until it returns expected HTTP status.
- `mbf::net::download <url> <dest_file> [expected_sha256]` — Download file and optionally verify SHA-256 checksum.
- `mbf::net::private_ip` / `mbf::net::public_ip` — Detect local and public IPv4 addresses.
- `mbf::net::is_port_open <port> [host]` / `mbf::net::wait_port <port> [host] [timeout_sec]` — Check or poll TCP port.
- `mbf::net::resolve_dns <domain>` — Resolve domain to IPv4 address.

---

## 9. `str` `[••]` — String Sanitization, Random Tokens & Cryptographic Hashes
Contains only non-trivial string and digest operations (for lowercase/uppercase, use native Bash `${var,,}` and `${var^^}`).

### Functions
- `mbf::str::trim <string>` — Strip leading and trailing whitespace.
- `mbf::str::slugify <string>` — Convert text into lowercase URL/filename slug (`my-site-01`).
- `mbf::str::random [length]` — Generate cryptographically random alphanumeric token (default: `24` chars).
- `mbf::str::sha256 <file>` — Compute SHA-256 hex digest of a file.
- `mbf::str::verify_sha256 <file> <expected_hex>` — Verify file checksum matches `<expected_hex>`.
- `mbf::str::hmac_sha256 <secret> <payload>` — Compute HMAC-SHA256 signature.
