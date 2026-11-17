# Library: `template` `[•••]` — Template Resolution & `{{VAR}}` Rendering

`lib/template.sh` renders `.tpl` configuration templates with required-variable validation (`# @mbf-vars:`), literal `{{VAR}}` substitution (safe with `&`, `\`, and URLs), atomic file writes, and a 3-tier lookup hierarchy so user scripts can override built-in `mbf` templates or bundle their own.

---

## Template Lookup Order (`mbf::template::resolve <name>`)

When you pass `"nginx/vhost-php.conf.tpl"` to `mbf::template::render`:
1. **Direct file path**: `./nginx/vhost-php.conf.tpl`
2. **Custom Template Directories**:
   - Colon-separated directories in `MBF_TEMPLATE_PATH`
   - `<caller_script_dir>/templates/<name>[.tpl]` *(lets your project override built-in templates without modifying `$MBF_HOME`)*
3. **Built-in MBF Templates**:
   - `$MBF_HOME/lib/templates/<name>[.tpl]` (`nginx/vhost-static.conf.tpl`, `nginx/vhost-php.conf.tpl`, `nginx/vhost-proxy.conf.tpl`, `script/script.sh.tpl`, `script/extension.sh.tpl`)

---

## Template File Convention (`# @mbf-vars:`)

Add `# @mbf-vars: VAR1 VAR2` on the first line of any `.tpl` file to require those variables before rendering. The `# @mbf-vars:` line is automatically stripped from the rendered output file.

```nginx
# @mbf-vars: DOMAIN ROOT_DIR PHP_VERSION
server {
    listen 80;
    server_name {{DOMAIN}};
    root {{ROOT_DIR}};

    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php{{PHP_VERSION}}-fpm.sock;
    }
}
```

---

## Function Reference & Examples

### 1. `mbf::template::render <tpl_name_or_path> <dest_file> [KEY=val...]`
Resolves the template, validates all `# @mbf-vars:` variables, replaces `{{VAR}}` placeholders, and writes `<dest_file>` atomically (skipped when `MBF_DRYRUN=1`).

```bash
mbf::use template

mbf::template::render "nginx/vhost-php.conf.tpl" "/etc/nginx/conf.d/shop.conf" \
    "DOMAIN=shop.example.com" \
    "ROOT_DIR=/var/www/magento2/pub" \
    "PHP_VERSION=8.2"
```

### 2. `mbf::template::render_str "<template_string>" [KEY=val...]`
Renders `{{VAR}}` placeholders in memory and prints the result to `stdout`. Explicit `KEY=val` arguments are applied first; any remaining `{{VAR}}` placeholders fall back to current shell variables.

```bash
export ENV_NAME="production"

out="$(mbf::template::render_str \
    "Connecting to {{DB_URL}} in {{ENV_NAME}}" \
    "DB_URL=mysql://user:p&ss@db.internal/app?ssl=1&timeout=5")"

echo "$out"
# Output: Connecting to mysql://user:p&ss@db.internal/app?ssl=1&timeout=5 in production
```

### 3. `mbf::template::resolve <name_or_path>`
Prints the resolved file path for `<name_or_path>`, or returns `1` if not found.

```bash
tpl_path="$(mbf::template::resolve "nginx/vhost-proxy.conf.tpl")"
echo "Using template: ${tpl_path}"
```

### 4. `mbf::template::validate_vars <tpl_name_or_path> [KEY=val...]`
Verifies that every variable listed in `# @mbf-vars:` is either passed as a `KEY=val` argument or set in the current environment. Returns `1` and logs the missing variable name if validation fails.

```bash
mbf::template::validate_vars "nginx/vhost-proxy.conf.tpl" \
    "DOMAIN=api.example.com" \
    "UPSTREAM_PORT=3000" || exit 1
```

### 5. `mbf::template::write_atomic <dest_file>`
Writes `stdin` to `<dest_file>` atomically via a temporary sibling file while preserving existing permissions and ownership.

```bash
printf 'APP_ENV=production\nAPP_DEBUG=false\n' | mbf::template::write_atomic "/var/www/app/.env"
```

### 6. `mbf::template::list`
Lists all discoverable `.tpl` templates across `MBF_TEMPLATE_PATH`, `./templates/`, and `$MBF_HOME/lib/templates/`.

```bash
mbf::template::list
```
