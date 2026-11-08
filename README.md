# mbf — Micro Bash Framework

A clean, modular, zero-bloat Bash micro-framework with a unified `mbf::*` namespace, separated core libraries (`lib/`), opt-in plugins (`plugins/`), and fast single-pass `awk` build tools (`tools/`).

---

## 1. Repository Layout

```text
mbf/
├── bin/mbf                 # CLI: init, update, export, compile, monitor, test, list, new
├── framework.sh            # Side-effect-free loader (mbf::use, mbf::init, mbf::strict, mbf::update)
├── install.sh              # One-command installer for ~/.bashrc & ~/.bash_profile
├── lib/                    # Core framework libraries
│   ├── log.sh              # mbf::log::{info,ok,warn,error,debug,stack_trace}, mbf::die
│   ├── exec.sh             # mbf::exec::{run,sudo,as_user,retry,scripts_in_dir,init_sudo}
│   ├── check.sh            # mbf::check::{cmd,cmds,env,root,is_linux,is_macos}
│   ├── fs.sh               # mbf::fs::{tmpfile,tmpdir,on_exit}
│   ├── args.sh             # mbf::args::{flag,option,parse,help}
│   └── config.sh           # mbf::config::{get,set,insert,ensure,delete_line,replace_line,replace_text,line_number,append_after_line}
├── plugins/                # Opt-in domain add-ons (loaded via mbf::use <plugin>)
│   ├── monitor.sh          # mbf::monitor::{resources,performance,logs,firewall,cron,history,report}
│   ├── notify.sh           # mbf::notify::{email,slack,telegram,alert}
│   ├── runtime.sh          # mbf::runtime::{pkg_manager,install_hint,ensure_pkg,download,check_node,npm_install,run_node,check_python,pip_install,run_python}
│   └── obfuscator.sh       # mbf::obfuscator::run
├── tools/                  # Build-time tools used by `bin/mbf`
│   ├── exporter.sh         # Single-pass awk tree-shaking script & bundle exporter
│   └── compiler.sh         # Standalone exporter + optional obfuscator + shc binary compiler
└── test/                   # Subshell-isolated automated unit & plugin test suites
```

---

## 2. Quick Installation & Updating

```bash
# Remote one-command install:
curl -fsSL https://raw.githubusercontent.com/ndthanhcom/mbf/master/install.sh | bash

# Local install:
bash install.sh --in-place

# Update to latest version via git pull:
mbf update
```

---

## 3. Writing Scripts with `mbf`

```bash
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::use config args exec

USAGE="Usage: $(basename "$0") [options] <config_file>"
mbf::args::flag   "v" "verbose" "MBF_DEBUG"   "Enable debug output and stack traces"
mbf::args::option "e" "env"     "TARGET_ENV"  "Target environment" "production"

function main() {
    mbf::args::parse "$@" || return 1
    local conf="${MBF_POSITIONAL_ARGS[0]:-app.conf}"

    mbf::log::info "Configuring $conf for $TARGET_ENV..."
    mbf::config::ensure "$conf" "env = $TARGET_ENV"
    mbf::config::set "$conf" "env" "$TARGET_ENV"
    mbf::log::ok "Done!"
}

main "$@"
```

---

## 4. Debugger & `/tmp` Logger (`MBF_DEBUG` & `MBF_LOG`)

* **`MBF_LOG=1`**: Appends all log entries and errors to `${MBF_LOG_FILE:-/tmp/mbf.log}`.
* **`MBF_DEBUG=1`**: Enables `mbf::log::debug` with `file:line:function` context, logs errors to `MBF_LOG_FILE`, and prints a full Bash call stack (`mbf::log::stack_trace`) on errors.

```bash
MBF_LOG=1 MBF_DEBUG=1 MBF_LOG_FILE=/tmp/app.log bash my_script.sh
```

---

## 5. Plugins (`plugins/`)

### System, Node.js & Python Integration (`mbf::use runtime`)
```bash
mbf::use runtime
mbf::runtime::ensure_pkg "jq" "jq" "https://jqlang.github.io/jq/"
mbf::runtime::run_node "worker.js" --port=3000
mbf::runtime::run_python "analyzer.py" --input=data.json
```

### Linux Server Monitoring (`mbf::use monitor` or `mbf monitor`)
```bash
mbf monitor all          # or: resources, performance, logs, firewall, cron, history
```

### Email, Slack & Telegram Alerts (`mbf::use notify`)
```bash
mbf::use notify
mbf::notify::email "ops@example.com" "[PROD] Alert" "Disk usage is at 92%"
mbf::notify::slack "Deployment completed" "$MBF_SLACK_WEBHOOK"
mbf::notify::telegram "High load on $(hostname)" "$MBF_TELEGRAM_BOT_TOKEN" "$MBF_TELEGRAM_CHAT_ID"
mbf::notify::alert "HIGH LOAD" "Load average is 12.4"
```

### Script Obfuscator (`mbf::use obfuscator`)
```bash
mbf::use obfuscator
mbf::obfuscator::run my_script.sh obfuscated_script.sh
```

---

## 6. Exporting Standalone Scripts & App Bundles (`mbf export`)

`mbf export` uses a single-pass `awk` call-graph analyzer to tree-shake unused functions while preserving module state blocks (`# mbf:state_start ... # mbf:state_end`):

```bash
# Export single standalone .sh script:
mbf export my_script.sh -o dist/my_script.sh

# Export polyglot directory bundle (script + .js/.py assets + package.json/requirements.txt + INSTALL.md):
mbf export polyglot_app.sh --bundle-dir dist/polyglot_bundle

# Export, obfuscate, and compile to native binary via shc:
mbf compile my_script.sh --obfuscate -o dist/my_binary
```

---

## 7. Running Automated Tests

```bash
mbf test
```
