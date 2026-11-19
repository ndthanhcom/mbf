# Extending MBF: Custom Libraries, Plugins & Templates

`mbf` is designed so your projects are never limited to built-in modules. Any script or repository can define its own **custom libraries**, **custom plugins**, and **custom `.tpl` templates** while remaining 100% compatible with `mbf::use`, single-pass tree-shaking (`mbf export`), and diagnostics (`mbf doctor`).

---

## 1. Project Directory Convention

When building a project powered by `mbf`, place your custom extensions and templates alongside your scripts:

```text
my-devops-project/
├── deploy-magento.sh             # Main script (`mbf::use log args exec magento varnish`)
├── lib/                          # Custom project libraries (auto-discovered by `mbf::use`)
│   └── magento.sh
├── plugins/                      # Custom project plugins (auto-discovered by `mbf::use`)
│   └── varnish.sh
└── templates/                    # Custom or overridden `.tpl` files (auto-discovered by `mbf::template`)
    ├── magento/
    │   └── env.php.tpl
    └── script/
        └── script.sh.tpl         # Overrides MBF's built-in script/script.sh.tpl!
```

### How Module Resolution Works (`mbf::use <name>`)
When your script calls `mbf::use magento`, `mbf` searches in this exact order:
1. **Explicit file path**: e.g. `mbf::use ./plugins/magento.sh`
2. **Custom Extension Paths**:
   - Directories listed in `MBF_EXT_PATH` (colon-separated: `export MBF_EXT_PATH="/opt/shared/mbf-exts:./exts"`)
   - `<caller_script_dir>/lib/<name>.sh` and `<caller_script_dir>/plugins/<name>.sh`
   - User-installed plugins directory (`MBF_USER_PLUGINS_DIR`, default `~/.local/share/mbf/plugins`, managed via `mbf plugin add|remove|list`)
3. **Built-in MBF Modules**:
   - `$MBF_HOME/lib/<name>.sh` and `$MBF_HOME/plugins/<name>.sh`

### How Template Resolution Works (`mbf::template::resolve <name>`)
When your script or plugin calls `mbf::template::render "magento/env.php.tpl" ...`:
1. **Explicit file path**: `./my-vhost.conf.tpl`
2. **Custom Template Paths**:
   - Directories in `MBF_TEMPLATE_PATH` (colon-separated)
   - `<caller_script_dir>/templates/<name>[.tpl]` *(allows overriding built-in `mbf` templates without modifying `$MBF_HOME`)*
3. **Built-in MBF Templates**:
   - `$MBF_HOME/lib/templates/<name>[.tpl]`

---

## 2. Scaffolding a Compliant Extension (`mbf new --ext`)

Generate a new extension skeleton with all strict rules pre-configured:

```bash
mbf new --ext plugins/magento.sh
```

This renders `lib/templates/script/extension.sh.tpl`:

```bash
#!/usr/bin/env bash
# @mbf-module: magento
# @mbf-api: 1
# mbf:requires log exec
# ==============================================================================
# Custom mbf Extension: magento
# ==============================================================================

# mbf:state_start
MBF_MAGENTO_DEFAULT="${MBF_MAGENTO_DEFAULT:-default}"
# mbf:state_end

# Internal helper function (prefixed with `_mbf_magento_`)
function _mbf_magento_validate() {
    local target="${1:-}"
    [ -n "$target" ] || return 1
}

# Public extension function
# Usage: mbf::magento::run <target>
function mbf::magento::run() {
    local target="${1:-}"
    if ! _mbf_magento_validate "$target"; then
        mbf::log::error "mbf::magento::run: target argument is required"
        return 1
    fi

    mbf::log::debug_ext "Executing mbf::magento::run for target='$target'"
    mbf::exec::run echo "Running magento on $target"
}
```

---

## 3. The 7 Strict Rules for Export-Compatible Extensions

Because `mbf export` uses a fast single-pass `awk` static call-graph analyzer to tree-shake unused functions, custom extensions **must** follow these 7 rules:

1. **Header Metadata**: Include `# @mbf-module: <name>` and `# @mbf-api: 1` at the top of the file. `mbf doctor` checks `# @mbf-api:` against `MBF_API_VERSION` to ensure forward compatibility.
2. **Declarative Dependencies**: Declare module dependencies using `# mbf:requires log exec config` in the header so both `mbf::use` and `mbf export` load them in topological order.
3. **State Blocks**: Wrap any global/default state variables inside `# mbf:state_start` and `# mbf:state_end` comments so `mbf export` preserves them at the top of exported scripts.
4. **`function` Keyword & Naming Convention**:
   - Always declare functions with the `function` keyword: `function mbf::<module>::<fn>() {`.
   - Public functions must use `mbf::<module>::<fn>` (or `<ns>::<module>::<fn>`).
   - Private helper functions must use `_mbf_<module>_<fn>`.
5. **Column-0 Closing Brace**: The closing `}` of every function must appear at column 0 on its own line (`^}$`).
6. **Never `exit` in Library Functions**: Return `0` or `1` status codes so callers can handle errors or roll back.
7. **Dry-Run, Strict-Mode & Template Compliance**:
   - **Dry-Run**: Wrap external commands in `mbf::exec::run` (or `mbf::system::as_root`); if your function writes files directly via `>` or `cat`, check `mbf::is_dryrun && return 0` first.
   - **Strict Mode (`set -Eeuo pipefail`)**: Capture non-zero exit codes with `local rc=0; some_cmd || rc=$?` instead of running `some_cmd; local rc=$?`, and use `grep ... || true` when zero matches are normal.
   - **Templates**: Resolve templates via `mbf::template::render`.

---

## 4. Troubleshooting Extensions (`MBF_DEBUG_EXT` & `mbf doctor`)

### A. Static Validation with `mbf doctor`
Run `mbf doctor` against your custom extension or main script before exporting:

```bash
mbf doctor plugins/magento.sh
mbf doctor deploy-magento.sh
```

`mbf doctor` verifies:
- `# @mbf-module:` and `# @mbf-api:` headers are valid and compatible.
- Every `# mbf:requires` and `mbf::use` target resolves to an existing file (printing the exact path).
- Every `mbf::template::render` / `resolve` target exists in `MBF_TEMPLATE_PATH`, `./templates/`, or `$MBF_HOME/lib/templates/`.
- All functions use the `function` keyword and match `<ns>::<module>::<fn>` or `_mbf_<module>_<fn>`.

### B. Runtime Resolution Tracing with `MBF_DEBUG_EXT=1`
If a script loads the wrong extension file or template, run it with `MBF_DEBUG_EXT=1`:

```bash
MBF_DEBUG_EXT=1 ./deploy-magento.sh --dry-run
```

Output:
```text
2026-11-16T01:30:00+0700 [EXT-DEBUG] (framework.sh:91) Loading module 'magento' from '/project/plugins/magento.sh' (requires: log exec template)
2026-11-16T01:30:00+0700 [EXT-DEBUG] (template.sh:40) Template 'magento/env.php.tpl' resolved to custom template '/project/templates/magento/env.php.tpl'
```

---

## 5. Publishing a Plugin or Extended-Script Repository (`README.md` Manifest)

Any Git repository that hosts MBF plugins (`plugins/*.sh`), templates (`templates/`), and/or extended scripts (`audit.sh`, `deploy.sh`) can be installed, tracked in `.installed_plugins`, updated, and removed cleanly via `mbf plugin`:

```bash
mbf plugin add github.com/<owner>/<repo>        # Supports github.com/<owner>/<repo>, HTTPS, SSH, or local dir
mbf plugin list                                 # View tracked packages in ~/.local/share/mbf/.installed_plugins
mbf plugin update [package_name]                # Update one or all installed git repos
mbf plugin run <package_name> <script.sh> [...] # Run an extended script bundled in the repo
mbf plugin remove <package_name>                # Remove repo + all its installed plugins & templates
```

### `README.md` Manifest Table Specification

Place the manifest table **at the top of your repository's `README.md`** wrapped in `<!-- mbf:manifest:start -->` and `<!-- mbf:manifest:end -->`. `mbf plugin add` parses this table directly—no separate `package.json` or YAML file is needed.

```markdown
# my-mbf-plugin

> Short description of what this plugin or extended-script repository does.

<!-- mbf:manifest:start -->
| Field | Value | Requirement |
| :--- | :--- | :--- |
| **name** | `mbf-linux-audit` | Mandatory |
| **version** | `1.0.0` | Mandatory |
| **mbf-compat** | `>=1.0.0 <=1.2.9` | Mandatory |
| **plugins** | `plugins/monitor.sh`, `plugins/security.sh` | Mandatory *(or `scripts`)* |
| **requires** | `log`, `exec`, `config`, `system`, `json` | Mandatory |
| **mbf-api** | `1` | Optional |
| **scripts** | `audit.sh` | Optional |
| **templates** | `templates/` | Optional |
| **system-deps** | `awk`, `grep`, `ss` | Optional |
| **plugin-deps** | `-` | Optional |
<!-- mbf:manifest:end -->
```

### Mandatory vs. Optional Manifest Rows

| Field | Requirement | Purpose |
| :--- | :--- | :--- |
| **`name`** | **Mandatory** | Unique package identifier recorded in `.installed_plugins` (used for `update`, `remove`, `run`). |
| **`version`** | **Mandatory** | Semantic version of this plugin repository (e.g. `1.0.0`). |
| **`mbf-compat`** | **Mandatory** | Supported MBF version range (`>=1.0.0 <=1.2.9`, `v1.0.0 - v1.2.9`, `>=1.0.0`, or `1.0.0`). Checked before install/update; users can switch via `mbf version switch <tag>`. |
| **`plugins`** | **Mandatory** *(if no `scripts`)* | Comma-separated relative paths to `.sh` plugin files (validated with `mbf doctor` and installed into `~/.local/share/mbf/plugins/`). |
| **`requires`** | **Mandatory** | Comma-separated MBF core modules required by this package (e.g. `log, exec, ssh`). |
| **`mbf-api`** | Optional | Required MBF API version integer (default: `1`). |
| **`scripts`** | Optional | Comma-separated relative paths to executable extended scripts (e.g. `audit.sh`) runnable via `mbf plugin run <name> <script>`. |
| **`templates`** | Optional | Relative template directory or file(s) (e.g. `templates/`) installed into `~/.local/share/mbf/templates/`. |
| **`system-deps`** | Optional | Comma-separated external OS binaries recommended on `PATH` (warns if missing). |
| **`plugin-deps`** | Optional | Comma-separated other MBF plugin repositories required (e.g. `github.com/org/other-plugin`). |
