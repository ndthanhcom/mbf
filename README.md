# mbf — Micro Bash Framework

A clean, modular, zero-bloat Bash micro-framework with a unified `mbf::*` namespace, **16 foundational core libraries** (`lib/`), **14 domain & SaaS plugins** (`plugins/`), and a **single-pass `awk` tree-shaking bundler** (`tools/`).

---

## 1. Repository Layout

```text
mbf/
├── bin/mbf                 # CLI: init, update, export, compile, monitor, test, list, new
├── framework.sh            # Side-effect-free loader (mbf::use, mbf::init, mbf::strict, mbf::update)
├── install.sh              # One-command installer for ~/.bashrc & ~/.bash_profile
├── lib/                    # 16 Core Foundational Libraries (zero external dependencies)
│   ├── log.sh              # mbf::log::{info,ok,warn,error,debug,stack_trace}, mbf::die
│   ├── exec.sh             # mbf::exec::{run,sudo,as_user,retry,scripts_in_dir,init_sudo}
│   ├── check.sh            # mbf::check::{cmd,cmds,env,root,is_linux,is_macos}
│   ├── fs.sh               # mbf::fs::{tmpfile,tmpdir,on_exit}
│   ├── args.sh             # mbf::args::{flag,option,parse,help}
│   ├── config.sh           # mbf::config::{get,set,insert,ensure,delete_line,replace_line,replace_text,line_number,append_after_line}
│   ├── str.sh              # mbf::str::{trim,lower,upper,slugify,is_alnum,is_domain,is_ip,is_email,random}
│   ├── json.sh             # mbf::json::{escape,object,array,get}
│   ├── http.sh             # mbf::http::{request,status_code,get_json,post_json,wait_ok}
│   ├── template.sh         # mbf::template::{render,write_atomic,backup,rollback}
│   ├── lock.sh             # mbf::lock::{acquire,release,is_step_done,mark_step,step_run}
│   ├── os.sh               # mbf::os::{distro,version,arch,pkg_manager,pkg_update,pkg_install,pkg_is_installed}
│   ├── service.sh          # mbf::service::{start,stop,restart,reload,enable,is_active,ensure_running}
│   ├── net.sh              # mbf::net::{private_ip,public_ip,is_port_open,wait_port,resolve_dns}
│   ├── user.sh             # mbf::user::{exists,ensure,add_ssh_key,remove_ssh_key,set_sudo_nopasswd}
│   └── crypto.sh           # mbf::crypto::{sha256,verify_sha256,hmac_sha256,cert_expiry_days}
├── plugins/                # 14 Opt-in Domain & SaaS Plugins (loaded via mbf::use <plugin>)
│   ├── monitor.sh          # mbf::monitor::{resources,performance,logs,firewall,cron,history,report}
│   ├── security.sh         # mbf::security::{audit_ssh,audit_system,harden_ssh,install_fail2ban}
│   ├── firewall.sh         # mbf::firewall::{backend,allow_port,deny_port,enable_baseline}
│   ├── cron.sh             # mbf::cron::{set,remove,enable,disable,list,run_guarded}
│   ├── webserver.sh        # mbf::webserver::{ensure_nginx,vhost_static,vhost_php,vhost_proxy,vhost_remove}
│   ├── ssl.sh              # mbf::ssl::{issue_letsencrypt,issue_self_signed,check_renewals}
│   ├── database.sh         # mbf::database::{ensure_mysql,ensure_postgres,ensure_redis,create_db_and_user,dump,restore}
│   ├── appstack.sh         # mbf::appstack::{ensure_php,deploy_git,install_wordpress}
│   ├── docker.sh           # mbf::docker::{ensure_installed,compose_up,compose_down,prune_safe}
│   ├── backup.sh           # mbf::backup::{archive_dir,upload_rsync,upload_s3,prune}
│   ├── notify.sh           # mbf::notify::{email,slack,telegram,alert}
│   ├── agent.sh            # mbf::agent::{send_event,collect_review_json}
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
mbf::use str json lock webserver ssl agent

# Idempotent step execution + SaaS webhook progress reporting
mbf::lock::acquire "provision_site" 10 || mbf::die "Another provisioning job is running"

mbf::lock::step_run "01_vhost" mbf::webserver::vhost_php "app.example.com" "/var/www/app" "8.2"
mbf::agent::send_event "job_101" "01_vhost" "completed" "Nginx vhost provisioned"
```

---

## 4. Exporting Standalone Scripts & App Bundles (`mbf export`)

`mbf export` uses a single-pass `awk` call-graph analyzer to tree-shake unused functions while preserving module state blocks (`# mbf:state_start ... # mbf:state_end`) and resolving `# mbf:requires` headers automatically:

```bash
# Export single standalone .sh script (ideal for SaaS-generated scripts):
mbf export site_builder.sh -o dist/site_builder.sh

# Export polyglot directory bundle (script + .js/.py assets + package.json/requirements.txt + INSTALL.md):
mbf export polyglot_app.sh --bundle-dir dist/polyglot_bundle

# Export, obfuscate, and compile to native binary via shc:
mbf compile site_builder.sh --obfuscate -o dist/site_builder
```

---

## 5. Running Automated Tests

```bash
mbf test
```
