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
    └── nginx/
        └── vhost-php.conf.tpl    # Overrides MBF's built-in nginx/vhost-php.conf.tpl!
```

### How Module Resolution Works (`mbf::use <name>`)
When your script calls `mbf::use magento`, `mbf` searches in this exact order:
1. **Explicit file path**: e.g. `mbf::use ./plugins/magento.sh`
2. **Custom Extension Paths**:
   - Directories listed in `MBF_EXT_PATH` (colon-separated: `export MBF_EXT_PATH="/opt/shared/mbf-exts:./exts"`)
   - `<caller_script_dir>/lib/<name>.sh` and `<caller_script_dir>/plugins/<name>.sh`
3. **Built-in MBF Modules**:
   - `$MBF_HOME/lib/<name>.sh` and `$MBF_HOME/plugins/<name>.sh`

### How Template Resolution Works (`mbf::template::resolve <name>`)
When your script or plugin calls `mbf::template::render "nginx/vhost-php.conf.tpl" ...`:
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
# @mbf-rank: ••
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

1. **Header Metadata**: Include `# @mbf-module: <name>` and `# @mbf-rank: ••` at the top of the file.
2. **Declarative Dependencies**: Declare module dependencies using `# mbf:requires log exec config` in the header so both `mbf::use` and `mbf export` load them in topological order.
3. **State Blocks**: Wrap any global/default state variables inside `# mbf:state_start` and `# mbf:state_end` comments so `mbf export` preserves them at the top of exported scripts.
4. **`function` Keyword & Naming Convention**:
   - Always declare functions with the `function` keyword: `function mbf::<module>::<fn>() {`.
   - Public functions must use `mbf::<module>::<fn>` (or `<ns>::<module>::<fn>`).
   - Private helper functions must use `_mbf_<module>_<fn>`.
5. **Column-0 Closing Brace**: The closing `}` of every function must appear at column 0 on its own line (`^}$`).
6. **Never `exit` in Library Functions**: Return `0` or `1` status codes so callers can handle errors or roll back.
7. **Dry-Run & Template Compliance**: Wrap state-mutating commands in `mbf::exec::run` (or check `mbf::is_dryrun`) and resolve templates via `mbf::template::render`.

---

## 4. Troubleshooting Extensions (`MBF_DEBUG_EXT` & `mbf doctor`)

### A. Static Validation with `mbf doctor`
Run `mbf doctor` against your custom extension or main script before exporting:

```bash
mbf doctor plugins/magento.sh
mbf doctor deploy-magento.sh
```

`mbf doctor` verifies:
- `# @mbf-module:` and `# @mbf-rank:` headers are present.
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
2026-11-12 / T01:30:00+0700 [EXT-DEBUG] (framework.sh:91) Loading module 'magento' from '/project/plugins/magento.sh' (requires: log exec template)
2026-11-12 / T01:30:00+0700 [EXT-DEBUG] (template.sh:40) Template 'nginx/vhost-php.conf.tpl' resolved to custom template '/project/templates/nginx/vhost-php.conf.tpl'
```
