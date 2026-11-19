# Library: `config` `[•••]` — Idempotent Config File Manipulation & Backup

`lib/config.sh` edits `.ini`, `.env`, `.conf`, `/etc/hosts`, and `sshd_config` files safely using literal `ENVIRON[...]` matching in `awk`.
- **No Regex Escaping Traps**: Values containing `/`, `&`, `|`, `\`, or URLs with query strings are written literally without escaping issues.
- **Exact Key Matching**: Updating `port` never accidentally modifies `export_port`.
- **Permissions Preserved**: File updates preserve the original file mode, ownership, and symlinks.

---

## Function Reference & Examples

### 1. `mbf::config::get <file> <key>`
Reads the value of `<key>` from a `key = value` or `key=value` file (if `<key>` appears multiple times, the last occurrence wins).

```bash
mbf::use config

mem_limit="$(mbf::config::get "/etc/php/8.2/fpm/php.ini" "memory_limit")"
echo "Current PHP memory_limit: ${mem_limit}"
```

### 2. `mbf::config::set <file> <key> <value>`
Updates `<key>` in place if it exists in `<file>`, or appends `<key> = <value>` to the end of the file if missing.

```bash
# Works safely with slashes, query parameters (&), and pipes (|)
mbf::config::set "/etc/php/8.2/fpm/php.ini" "memory_limit" "2G"
mbf::config::set "/etc/php/8.2/fpm/php.ini" "sendmail_path" "/usr/local/bin/mhsendmail"
mbf::config::set "/opt/app/.env" "WEBHOOK_URL" "https://saas.example.com/hook?env=prod&ch=slack|tg"
```

### 3. `mbf::config::get_directive <file> <Key>`
Reads a space-separated directive (`Key value`, such as in `/etc/ssh/sshd_config` or `nginx.conf`). Matching is case-insensitive and the **first** active occurrence wins (matching OpenSSH semantics).

```bash
ssh_port="$(mbf::config::get_directive "/etc/ssh/sshd_config" "Port" || echo 22)"
root_login="$(mbf::config::get_directive "/etc/ssh/sshd_config" "PermitRootLogin" || echo unset)"
```

### 4. `mbf::config::insert <file> <line>`
Appends `<line>` unconditionally to the end of `<file>`.

```bash
mbf::config::insert "/etc/sysctl.conf" "vm.swappiness = 10"
```

### 5. `mbf::config::ensure <file> <line>`
Idempotently ensures `<line>` exists in `<file>` (creates the file if missing; appends `<line>` only if no exact match exists).

```bash
# Safe to run 100 times — adds the line only once:
mbf::config::ensure "/etc/hosts" "127.0.0.1 shop.magento.local"
```

### 6. `mbf::config::ensure_block <file> <block_id> <multiline_content> [top]`
Manages a named multi-line section delimited by `# BEGIN MBF:<block_id>` and `# END MBF:<block_id>`.
- If the block already exists, its contents are updated **in place** (keeping its position in the file).
- If the block does not exist, it is appended to the end of the file (or inserted at the top when `top` is passed as the 4th argument).

```bash
mbf::config::ensure_block "/etc/hosts" "docker_cluster" \
'172.20.0.10 mysql.internal
172.20.0.11 redis.internal
172.20.0.12 opensearch.internal'
```

Result in `/etc/hosts`:
```text
# BEGIN MBF:docker_cluster
172.20.0.10 mysql.internal
172.20.0.11 redis.internal
172.20.0.12 opensearch.internal
# END MBF:docker_cluster
```

### 7. `mbf::config::delete_line <file> <pattern>`
Removes every line containing the literal text `<pattern>`.

```bash
mbf::config::delete_line "/etc/hosts" "old-staging.internal"
```

### 8. `mbf::config::replace_line <file> <pattern> <new_line>`
Replaces every line containing the literal text `<pattern>` with `<new_line>`.

```bash
mbf::config::replace_line "/etc/ssh/sshd_config" "PermitRootLogin" "PermitRootLogin no"
```

### 9. `mbf::config::replace_text <file> <search> <replacement>`
Replaces all occurrences of the literal substring `<search>` with `<replacement>` across `<file>`.

```bash
mbf::config::replace_text "/etc/nginx/conf.d/app.conf" "php8.1-fpm.sock" "php8.2-fpm.sock"
```

### 10. `mbf::config::line_number <file> <text>` & `mbf::config::append_after_line <file> <line_no> <text>`
Finds the 1-based line number of the first occurrence of `<text>` and inserts a new line immediately after it.

```bash
if ln="$(mbf::config::line_number "/etc/nginx/nginx.conf" "http {")"; then
    mbf::config::append_after_line "/etc/nginx/nginx.conf" "$ln" "    client_max_body_size 64M;"
fi
```

### 11. `mbf::config::backup <file>` & `mbf::config::rollback <file>`
Saves a `<file>.mbf.bak` copy (preserving permissions) before making risky edits, and restores it if validation fails.

```bash
mbf::config::backup "/etc/nginx/nginx.conf"
mbf::config::replace_text "/etc/nginx/nginx.conf" "worker_processes auto;" "worker_processes 8;"

if ! nginx -t 2>/dev/null; then
    mbf::config::rollback "/etc/nginx/nginx.conf"
fi
```

### 12. `mbf::config::load_env <env_file> [override:0|1]`
Safely parses `KEY=VALUE` lines from a `.env` file **without `source` or `eval`** (preventing arbitrary shell code execution) and exports them. Existing environment variables are preserved unless `[override]` is `1`.

```bash
mbf::config::load_env ".env" 0
```

### 13. `mbf::config::read_secret <VAR_NAME> [fallback_file]`
Reads a secret into `<VAR_NAME>` following the Docker/Kubernetes `<VAR_NAME>_FILE` convention (or `[fallback_file]` / existing env var) and automatically registers its value with `mbf::log::redact` so it never leaks into logs.

```bash
export DB_PASSWORD_FILE="/run/secrets/db_password"
mbf::config::read_secret DB_PASSWORD
```
