# Library: `log` `[••••]` — Structured Logging & Diagnostics

`lib/log.sh` is loaded automatically by `framework.sh`. It provides ISO-8601 timestamped terminal logging, file logging, stack traces, `set -x` tracing, and dedicated `[EXT-DEBUG]` diagnostics for custom extensions and templates.

---

## Output Stream Contract

| Function | Default Stream | With `MBF_LOG_STDERR=1` | Purpose |
| :--- | :--- | :--- | :--- |
| `mbf::log::info` | `stdout` | `stderr` | General progress messages |
| `mbf::log::ok` | `stdout` | `stderr` | Successful step completion |
| `mbf::log::warn` | `stderr` | `stderr` | Non-fatal warnings |
| `mbf::log::error` | `stderr` | `stderr` | Errors (prints stack trace if `MBF_DEBUG=1`) |
| `mbf::log::debug` | `stderr` | `stderr` | Caller `file:line:func` debug trace (`MBF_DEBUG=1`) |
| `mbf::log::debug_ext` | `stderr` | `stderr` | Extension/template lookup trace (`MBF_DEBUG_EXT=1`) |

> [!TIP]
> Set `export MBF_LOG_STDERR=1` when writing functions whose `stdout` is captured via `result="$(my_func)"`. That way, `mbf::log::info` messages appear on the terminal (`stderr`) without being mixed into `$result`.

---

## Environment Variables

- `MBF_LOG=1` — Append all log levels to `MBF_LOG_FILE`.
- `MBF_LOG_FILE="/var/log/my-script.log"` — Log file path (default: `/tmp/mbf.log`).
- `MBF_LOG_STDERR=1` — Route `info` and `ok` messages to `stderr`.
- `MBF_DEBUG=1` — Enable `mbf::log::debug`, stack traces on error, and automatic error file logging.
- `MBF_DEBUG_EXT=1` — Enable `mbf::log::debug_ext` resolution traces.
- `NO_COLOR=1` — Disable ANSI color codes for plain-text CI logs.

---

## Function Reference & Examples

### 1. `mbf::log::info <message>`
Logs an informational message in cyan. Backslashes (such as Windows paths `C:\new\table`) are printed literally.

```bash
mbf::log::info "Starting Nginx configuration check..."
```

### 2. `mbf::log::ok <message>`
Logs a success message in green.

```bash
mbf::log::ok "Database migration completed in 4s."
```

### 3. `mbf::log::warn <message>`
Logs a warning message in yellow to `stderr`.

```bash
mbf::log::warn "Disk usage on /var is above 80%."
```

### 4. `mbf::log::error <message>`
Logs an error message in red to `stderr`. When `MBF_DEBUG=1` is set, it also prints the current Bash call stack and writes the error to `MBF_LOG_FILE`.

```bash
mbf::log::error "Failed to connect to Redis on 127.0.0.1:6379"
```

### 5. `mbf::log::debug <message>`
Logs a purple `[DEBUG] (file:line:function)` message to `stderr` and `MBF_LOG_FILE` when `MBF_DEBUG=1` is active. No-op when `MBF_DEBUG=0`.

```bash
MBF_DEBUG=1
mbf::log::debug "Resolved upstream port=${OPT_PORT}"
# Output: 2026-11-16T10:00:00+0700 [DEBUG] (deploy.sh:24:main) Resolved upstream port=8080
```

### 6. `mbf::log::debug_ext <message>`
Logs a purple `[EXT-DEBUG] (file:line)` message when `MBF_DEBUG_EXT=1` (or `MBF_DEBUG=1`) is set. Used to trace custom extension and template resolution.

```bash
MBF_DEBUG_EXT=1
mbf::log::debug_ext "Loaded custom varnish config from ${conf_path}"
```

### 7. `mbf::log::write_file <level> <message>`
Appends a plain-text timestamped entry directly to `MBF_LOG_FILE` (creating parent directories if needed), regardless of whether `MBF_LOG=1` is set.

```bash
mbf::log::write_file "AUDIT" "User ${USER} rotated production API keys"
```

### 8. `mbf::log::is_file_enabled` / `mbf::log::is_debug` / `mbf::log::is_debug_ext`
Predicates that return `0` when file logging, debug mode, or extension debug mode is active.

```bash
if mbf::log::is_debug; then
    mbf::log::info "Debug mode is active (log file: ${MBF_LOG_FILE})"
fi

if mbf::log::is_file_enabled; then
    echo "All logs are being saved to ${MBF_LOG_FILE}"
fi

if mbf::log::is_debug_ext; then
    echo "Extension resolution tracing is enabled"
fi
```

### 9. `mbf::log::stack_trace`
Prints the current Bash function call stack (`FUNCNAME`, `BASH_SOURCE`, `BASH_LINENO`).

```bash
function inner_step() {
    mbf::log::stack_trace
}
inner_step
```

### 10. `mbf::log::xtrace_on` & `mbf::log::xtrace_off`
Enables or disables `set -x` command tracing with a readable `+(file:line): func():` prompt prefix.

```bash
mbf::log::xtrace_on
tar -czf /tmp/app.tar.gz /var/www/app
mbf::log::xtrace_off
```

### 11. `mbf::die <message>`
Logs a fatal error message via `mbf::log::error` and terminates the script immediately with `exit 1`.

```bash
[ -f "/etc/nginx/nginx.conf" ] || mbf::die "Nginx configuration file not found!"
```

### 12. `mbf::log::redact <secret1> [secret2...]`
Registers sensitive strings (tokens, passwords, webhook URLs) to be masked as `***` across all terminal, JSON (`MBF_LOG_FORMAT=json`), CI (`MBF_LOG_CI=1`), and file log output. ANSI colors are automatically disabled when stdout is not a TTY (override with `FORCE_COLOR=1`).

```bash
mbf::log::redact "$API_TOKEN" "$DB_PASSWORD"
MBF_LOG_FORMAT=json mbf::log::info "Connecting with token=${API_TOKEN}"
# Output: {"timestamp":"...","level":"INFO","message":"Connecting with token=***"}
```
