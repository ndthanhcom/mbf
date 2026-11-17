# Plugin: `webserver` `[••]` — Nginx Vhosts, SSL Lifecycle & Application Stacks

`plugins/webserver.sh` provisions Nginx virtual hosts from `.tpl` templates (with automatic `.mbf.bak` rollback if `nginx -t` fails), issues and monitors Let's Encrypt or self-signed TLS certificates, installs PHP-FPM extensions, and deploys Git repositories.

---

## Environment Variables

- `MBF_NGINX_SITES_DIR` — Target directory for generated Nginx `.conf` files (default: `/etc/nginx/conf.d`).
- `MBF_TEMPLATE_PATH` — Optional custom template directory to override `nginx/vhost-static.conf.tpl`, `nginx/vhost-php.conf.tpl`, or `nginx/vhost-proxy.conf.tpl`.

---

## Function Reference & Examples

### 1. `mbf::webserver::ensure_nginx`
Installs Nginx if missing and ensures the `nginx` service is enabled and running.

```bash
mbf::use webserver

mbf::webserver::ensure_nginx
```

### 2. `mbf::webserver::vhost_static <domain> <root_dir>`
Renders `nginx/vhost-static.conf.tpl` to `${MBF_NGINX_SITES_DIR}/<domain>.conf`, validates with `nginx -t` (rolling back on error), and reloads Nginx.

```bash
mbf::webserver::vhost_static "docs.example.com" "/var/www/docs/public"
```

### 3. `mbf::webserver::vhost_php <domain> <root_dir> [php_version]`
Renders `nginx/vhost-php.conf.tpl` configured for `unix:/run/php/php<php_version>-fpm.sock` (default: `8.2`), validates with `nginx -t`, and reloads Nginx.

```bash
mbf::webserver::vhost_php "shop.example.com" "/var/www/magento2/pub" "8.2"
```

### 4. `mbf::webserver::vhost_proxy <domain> <upstream_port>`
Renders `nginx/vhost-proxy.conf.tpl` to reverse-proxy traffic from `<domain>` to `http://127.0.0.1:<upstream_port>`, validates with `nginx -t`, and reloads Nginx.

```bash
mbf::webserver::vhost_proxy "jenkins.example.com" 8080
```

### 5. `mbf::webserver::vhost_remove <domain>`
Removes `${MBF_NGINX_SITES_DIR}/<domain>.conf` and reloads Nginx (respects `MBF_DRYRUN=1`).

```bash
mbf::webserver::vhost_remove "old-staging.example.com"
```

### 6. `mbf::webserver::ssl_letsencrypt <domain> <email> [webroot_dir]`
Installs `certbot` if missing and provisions a Let's Encrypt certificate non-interactively (using `--webroot -w <webroot_dir>` if provided, or `--nginx --redirect` otherwise).

```bash
# Using the Nginx plugin with automatic HTTPS redirect:
mbf::webserver::ssl_letsencrypt "shop.example.com" "ops@example.com"

# Or using webroot validation:
mbf::webserver::ssl_letsencrypt "shop.example.com" "ops@example.com" "/var/www/magento2/pub"
```

### 7. `mbf::webserver::ssl_self_signed <domain> <dest_dir> [days]`
Generates a 2048-bit RSA self-signed certificate (`<domain>.crt`) and private key (`<domain>.key`) in `<dest_dir>` valid for `[days]` (default: `365`).

```bash
mbf::webserver::ssl_self_signed "magento.local" "/etc/nginx/ssl" 365
```

### 8. `mbf::webserver::ssl_expiry_days <pem_file_or_domain>` & `mbf::webserver::ssl_check_renewals [certs_dir] [warn_days]`
- `ssl_expiry_days`: Prints the number of days remaining before a local `.crt`/`.pem` file or remote `domain:443` certificate expires (compatible with GNU `date` and macOS BSD `date`).
- `ssl_check_renewals`: Scans `[certs_dir]` (default: `/etc/letsencrypt/live`) and returns `1` with a warning if any certificate expires within `[warn_days]` (default: `14`).

```bash
days="$(mbf::webserver::ssl_expiry_days "/etc/letsencrypt/live/shop.example.com/fullchain.pem")"
echo "SSL certificate expires in ${days} days"

# Warn if any certificate in /etc/letsencrypt/live expires within 14 days:
mbf::webserver::ssl_check_renewals "/etc/letsencrypt/live" 14
```

### 9. `mbf::webserver::ensure_php [php_version] [extra_extensions...]`
Installs PHP-FPM (`php<ver>-fpm`, `cli`, `common`, `mysql`, `xml`, `curl`, `mbstring`, `zip`) plus any extra extensions, and ensures the `php<ver>-fpm` service is running.

```bash
mbf::webserver::ensure_php "8.2" "intl" "bcmath" "gd" "soap"
```

### 10. `mbf::webserver::deploy_git <app_dir> <repo_url> [branch] [build_cmd]`
Clones `<repo_url>` into `<app_dir>` (or fetches and fast-forward pulls `[branch]` if `<app_dir>/.git` already exists), then runs optional `[build_cmd]` inside `<app_dir>`.

```bash
mbf::webserver::deploy_git \
    "/var/www/app" \
    "https://github.com/example/webapp.git" \
    "main" \
    "composer install --no-dev --optimize-autoloader"
```
