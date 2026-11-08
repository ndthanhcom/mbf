# mbf — Micro Bash Framework

A lightweight, modular, zero-bloat Bash micro-framework for writing maintainable shell scripts, integrating with Node.js/Python/system programs, monitoring Linux servers, sending alerts, and exporting scripts as standalone `.sh` files, multi-file app bundles, or compiled binaries.

---

## 1. Quick Installation & Updating

Run the one-command installer (configures `MBF_HOME` and adds `mbf` to your `PATH` in `~/.bashrc` / `~/.bash_profile`):

```bash
curl -fsSL https://raw.githubusercontent.com/ndthanhcom/mbf/master/install.sh | bash
```

Or install from a local clone:

```bash
bash install.sh --in-place
```

Update `mbf` to the latest version at any time:

```bash
mbf update
# or inside a script:
mbf_update
```

---

## 2. Writing Scripts with `mbf`

Include `mbf` at the top of any script and load only the modules you need via `mbf_use` (or legacy `_import`):

```bash
#!/usr/bin/env bash
source "$(mbf --init)"
mbf_use log config args runtime monitor notify

USAGE="Usage: $(basename "$0") [options]"
mbf_arg_flag   "v" "verbose" "MBF_VERBOSE" "Enable verbose debug output"
mbf_arg_option "e" "env"     "TARGET_ENV"  "Target environment" "dev"

function main() {
    mbf_parse_args "$@"
    log_info "Deploying to environment: $TARGET_ENV"
}

main "$@"
```

### Available Modules (`lib/`)

| Module | Functions |
| :--- | :--- |
| **`core`** (`framework.sh`) | `mbf_use`, `_import`, `mbf_update`, `mbf_strict_mode`, `mbf_on_exit`, `mbf_mktemp_file`, `mbf_mktemp_dir`, `function_exists`, `in_list`, `in_file`, `get_pwd`, `get_script_dir` |
| **`log`** (`lib/log.sh`) | `log_info`, `log_success`, `log_warn`, `log_error`, `log_debug`, `die`, `mbf_write_log`, `mbf_debug_stack_trace`, `mbf_enable_xtrace`, `mbf_disable_xtrace`, `print_with_color`, `print_step_msg` |
| **`exec`** (`lib/exec.sh`) | `run_cmd`, `run_retry`, `run_cmd_by_user`, `run_parts_by_dir`, `run_scripts_by_dir`, `run_times`, `run_continously`, `execute`, `initialize_sudo` |
| **`check`** (`lib/check.sh`) | `validate_program`, `check_requirements`, `require_env`, `require_root`, `is_linux`, `is_macos` |
| **`config`** (`lib/config.sh`) | `insert_config`, `ensure_config`, `modify_config_value`, `get_config_value`, `delete_line`, `replace_line`, `replace_text_in_file`, `get_text_linenumber`, `append_after_linenumber`, `yq_append_array_item`, `yq_append_node` |
| **`args`** (`lib/args.sh`) | `mbf_arg_flag`, `mbf_arg_option`, `mbf_parse_args`, `print_help`, `process_params` |
| **`runtime`** (`lib/runtime.sh`) | `runtime_detect_pkg_manager`, `runtime_install_instruction`, `runtime_ensure_pkg`, `runtime_download_app`, `runtime_check_node`, `runtime_install_npm_deps`, `runtime_run_node`, `runtime_eval_node`, `runtime_check_python`, `runtime_install_pip_deps`, `runtime_run_python`, `runtime_eval_python` |
| **`monitor`** (`lib/monitor.sh`) | `monitor_resources`, `monitor_performance`, `monitor_logs`, `monitor_firewall`, `monitor_cron`, `monitor_history`, `monitor_server_report` |
| **`notify`** (`lib/notify.sh`) | `notify_email`, `notify_slack`, `notify_telegram`, `notify_alert` |
| **`auth`** (`lib/auth.sh`) | `generate_token`, `validate_token` |
| **`exporter`** (`lib/exporter.sh`) | `mbf_export_script`, `process_inline` |
| **`obfuscator`** (`lib/obfuscator.sh`) | `obfuscate` |
| **`compiler`** (`lib/compiler.sh`) | `compile` |

---

## 3. System, Node.js & Python Integration (`lib/runtime.sh`)

Check or install system packages, download binaries, and execute interactive or CLI Node.js and Python scripts:

```bash
mbf_use runtime

# Ensure a system tool is installed (prints OS-specific install command, or auto-installs if MBF_AUTO_INSTALL=1)
runtime_ensure_pkg "jq" "jq" "https://jqlang.github.io/jq/"

# Check Node.js & run a Node.js script interactively or with arguments
runtime_check_node 18
runtime_install_npm_deps
runtime_run_node "worker.js" --env=prod

# Check Python 3 & run a Python script interactively or with arguments
runtime_check_python 3
runtime_install_pip_deps "requirements.txt"
runtime_run_python "analyzer.py" --input=data.json
```

---

## 4. Debugger & `/tmp` Logger (`MBF_DEBUG` & `MBF_LOG`)

Control logging and debugging behavior via environment variables without modifying your script:

* **`MBF_LOG=1`**: Appends all log entries and command execution errors to `${MBF_LOG_FILE:-/tmp/mbf.log}` for server monitoring.
* **`MBF_DEBUG=1`**:
  * Enables `log_debug` messages with caller `file:line:function` metadata.
  * Automatically prints a full Bash call stack trace (`mbf_debug_stack_trace`) whenever `log_error` or a `run_cmd` failure occurs, and appends errors to `/tmp/mbf.log`.

```bash
MBF_LOG=1 MBF_DEBUG=1 MBF_LOG_FILE=/tmp/my_app.log bash my_script.sh
```

---

## 5. Linux Server Monitoring & Review (`lib/monitor.sh`)

Run a comprehensive server review from the CLI or inside any script:

```bash
mbf monitor all
mbf monitor resources
mbf monitor performance
mbf monitor logs /var/log/syslog 20
mbf monitor firewall
mbf monitor cron
mbf monitor history
```

---

## 6. Server Email, Slack & Telegram Alerts (`lib/notify.sh`)

```bash
mbf_use notify

notify_email "ops@example.com" "[PROD] Disk Warning" "Partition / is at 91%"

export MBF_SLACK_WEBHOOK="https://hooks.slack.com/services/XXX/YYY/ZZZ"
notify_slack "Deployment completed on $(hostname)"

export MBF_TELEGRAM_BOT_TOKEN="123456:ABC-DEF"
export MBF_TELEGRAM_CHAT_ID="-100123456789"
notify_telegram "High load detected on $(hostname)"

# Send to all configured channels at once:
notify_alert "Server Alert" "High CPU usage detected"
```

---

## 7. Exporting Standalone Scripts & Polyglot App Bundles (Zero Bloatware)

Use `mbf export` to bundle a script that uses `mbf` with **function-level tree-shaking**:

```bash
# Single standalone .sh file:
mbf export my_script.sh -o dist/my_script.sh

# Multi-file bundle directory (copies related Node.js/Python scripts, package.json, requirements.txt, and generates INSTALL.md):
mbf export polyglot_app.sh --bundle-dir dist/polyglot_bundle
```

---

## 8. Running Automated Tests

```bash
mbf test
# or directly:
bash test/run.sh
```
