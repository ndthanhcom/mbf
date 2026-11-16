#!/usr/bin/env bash
# @mbf-module: webserver
# @mbf-rank: ••
# mbf:requires log exec system config template
# ==============================================================================
# mbf plugin: webserver
# Automated Nginx Vhost Provisioner (via `lib/templates/`), SSL Certificates
# (Let's Encrypt & Self-Signed), PHP-FPM Setup, and Git Application Deployment
# ==============================================================================

# mbf:state_start
MBF_NGINX_SITES_DIR="${MBF_NGINX_SITES_DIR:-/etc/nginx/conf.d}"
# mbf:state_end

# Ensure Nginx is installed and running
function mbf::webserver::ensure_nginx() {
    if ! command -v nginx >/dev/null 2>&1; then
        mbf::system::pkg_install nginx || return 1
    fi
    mbf::system::service_ensure nginx
}

# Validate Nginx configuration with `nginx -t` and reload; if validation fails,
# roll back to the previous `.mbf.bak` vhost file (or delete the newly created file).
function _mbf_nginx_validate_and_reload() {
    local conf_file="$1"
    local had_backup="${2:-0}"
    if mbf::is_dryrun; then
        return 0
    fi
    if command -v nginx >/dev/null 2>&1 && [ "$MBF_NGINX_SITES_DIR" == "/etc/nginx/conf.d" ]; then
        if ! nginx -t 2>/dev/null; then
            mbf::log::error "Nginx config test failed for $conf_file; rolling back"
            if [ "$had_backup" -eq 1 ] && [ -f "${conf_file}.mbf.bak" ]; then
                mbf::config::rollback "$conf_file"
            else
                rm -f "$conf_file"
            fi
            return 1
        fi
        rm -f "${conf_file}.mbf.bak"
        mbf::system::service reload nginx
    fi
    return 0
}

function _mbf_nginx_render_vhost() {
    local tpl="$1"
    local conf_file="$2"
    shift 2
    local had_backup=0
    if [ -f "$conf_file" ]; then
        mbf::config::backup "$conf_file" && had_backup=1
    fi
    if ! mbf::template::render "$tpl" "$conf_file" "$@"; then
        [ "$had_backup" -eq 1 ] && rm -f "${conf_file}.mbf.bak"
        return 1
    fi
    _mbf_nginx_validate_and_reload "$conf_file" "$had_backup"
}

# Create a static site Nginx virtual host using `nginx/vhost-static.conf.tpl`
# Usage: mbf::webserver::vhost_static <domain> <root_dir>
function mbf::webserver::vhost_static() {
    local domain="$1"
    local root_dir="$2"
    local conf_file="${MBF_NGINX_SITES_DIR}/${domain}.conf"

    mbf::is_dryrun || mkdir -p "$MBF_NGINX_SITES_DIR" "$root_dir" 2>/dev/null || true
    _mbf_nginx_render_vhost "nginx/vhost-static.conf.tpl" "$conf_file" \
        "DOMAIN=${domain}" \
        "ROOT_DIR=${root_dir}"
}

# Create a PHP-FPM site Nginx virtual host using `nginx/vhost-php.conf.tpl`
# Usage: mbf::webserver::vhost_php <domain> <root_dir> [php_version]
function mbf::webserver::vhost_php() {
    local domain="$1"
    local root_dir="$2"
    local php_ver="${3:-8.2}"
    local conf_file="${MBF_NGINX_SITES_DIR}/${domain}.conf"

    mbf::is_dryrun || mkdir -p "$MBF_NGINX_SITES_DIR" "$root_dir" 2>/dev/null || true
    _mbf_nginx_render_vhost "nginx/vhost-php.conf.tpl" "$conf_file" \
        "DOMAIN=${domain}" \
        "ROOT_DIR=${root_dir}" \
        "PHP_VERSION=${php_ver}"
}

# Create a reverse-proxy Nginx virtual host using `nginx/vhost-proxy.conf.tpl`
# Usage: mbf::webserver::vhost_proxy <domain> <upstream_port>
function mbf::webserver::vhost_proxy() {
    local domain="$1"
    local port="$2"
    local conf_file="${MBF_NGINX_SITES_DIR}/${domain}.conf"

    mbf::is_dryrun || mkdir -p "$MBF_NGINX_SITES_DIR" 2>/dev/null || true
    _mbf_nginx_render_vhost "nginx/vhost-proxy.conf.tpl" "$conf_file" \
        "DOMAIN=${domain}" \
        "UPSTREAM_PORT=${port}"
}

# Remove an Nginx virtual host (respects MBF_DRYRUN=1)
function mbf::webserver::vhost_remove() {
    local domain="$1"
    local conf_file="${MBF_NGINX_SITES_DIR}/${domain}.conf"
    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would remove Nginx vhost $conf_file"
        return 0
    fi
    rm -f "$conf_file"
    _mbf_nginx_validate_and_reload "$conf_file" 0
}

# Provision a Let's Encrypt certificate for `<domain>` via certbot
# Usage: mbf::webserver::ssl_letsencrypt <domain> <email> [webroot_dir]
function mbf::webserver::ssl_letsencrypt() {
    local domain="$1"
    local email="$2"
    local webroot="${3:-}"

    if [ -z "$domain" ] || [ -z "$email" ]; then
        mbf::log::error "mbf::webserver::ssl_letsencrypt: <domain> and <email> are required"
        return 1
    fi

    if ! command -v certbot >/dev/null 2>&1 && ! mbf::is_dryrun; then
        mbf::system::pkg_install certbot python3-certbot-nginx || return 1
    fi

    if [ -n "$webroot" ]; then
        mbf::system::as_root certbot certonly --non-interactive --agree-tos -m "$email" --webroot -w "$webroot" -d "$domain"
    else
        mbf::system::as_root certbot --nginx --non-interactive --agree-tos -m "$email" -d "$domain" --redirect
    fi
}

# Generate a self-signed TLS certificate and private key in `<dest_dir>`
# Usage: mbf::webserver::ssl_self_signed <domain> <dest_dir> [days]
function mbf::webserver::ssl_self_signed() {
    local domain="$1"
    local dest_dir="$2"
    local days="${3:-365}"

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would generate self-signed cert for $domain in $dest_dir"
        return 0
    fi

    mkdir -p "$dest_dir" || return 1
    MSYS2_ARG_CONV_EXCL="/CN=" openssl req -x509 -nodes -days "$days" -newkey rsa:2048 \
        -keyout "${dest_dir}/${domain}.key" \
        -out "${dest_dir}/${domain}.crt" \
        -subj "/CN=${domain}" 2>/dev/null
}

# Convert an OpenSSL ASN1_TIME string (e.g. `Nov 14 10:00:00 2027 GMT`) to epoch seconds
# across GNU `date -d` (Linux/Git Bash) and BSD `date -j -f` (macOS).
function _mbf_parse_openssl_date() {
    local date_str="$1"
    if date -d "$date_str" +%s 2>/dev/null; then
        return 0
    fi
    local clean
    clean="$(printf '%s' "$date_str" | tr -s ' ')"
    date -j -u -f "%b %e %T %Y %Z" "$clean" +%s 2>/dev/null || \
        date -j -u -f "%b %d %T %Y %Z" "$clean" +%s 2>/dev/null
}

# Return remaining days before an SSL certificate (PEM file or domain:443) expires
# Usage: mbf::webserver::ssl_expiry_days <pem_file_or_domain>
function mbf::webserver::ssl_expiry_days() {
    local target="$1"
    local end_date_str end_epoch now_epoch

    if ! command -v openssl >/dev/null 2>&1; then
        mbf::log::error "openssl is required to inspect SSL certificates"
        return 1
    fi

    if [ -f "$target" ]; then
        end_date_str="$(openssl x509 -enddate -noout -in "$target" 2>/dev/null | cut -d= -f2)"
    else
        end_date_str="$( </dev/null openssl s_client -servername "$target" -connect "${target}:443" 2>/dev/null | openssl x509 -enddate -noout 2>/dev/null | cut -d= -f2)"
    fi

    [ -z "$end_date_str" ] && return 1
    end_epoch="$(_mbf_parse_openssl_date "$end_date_str")" || return 1
    now_epoch="$(date +%s)"
    printf '%d\n' $(( (end_epoch - now_epoch) / 86400 ))
}

# Check all `.crt` / `fullchain.pem` files in a directory and warn if expiring within `<warn_days>`
# Usage: mbf::webserver::ssl_check_renewals [certs_dir] [warn_days]
function mbf::webserver::ssl_check_renewals() {
    local certs_dir="${1:-/etc/letsencrypt/live}"
    local warn_days="${2:-14}"
    local rc=0 cert days

    [ -d "$certs_dir" ] || return 0

    while IFS= read -r -d $'\0' cert; do
        if days="$(mbf::webserver::ssl_expiry_days "$cert")"; then
            if [ "$days" -le "$warn_days" ]; then
                mbf::log::warn "Certificate $cert expires in ${days} days (<= ${warn_days})"
                rc=1
            else
                mbf::log::info "Certificate $cert valid for ${days} days"
            fi
        fi
    done < <(find "$certs_dir" -type f \( -name "*.crt" -o -name "fullchain.pem" \) -print0 2>/dev/null)

    return $rc
}

# Ensure PHP-FPM and common extensions are installed for the given version
# Usage: mbf::webserver::ensure_php [php_version] [extra_exts...]
function mbf::webserver::ensure_php() {
    local ver="${1:-8.2}"
    shift 1 2>/dev/null || true

    local -a pkgs=("php${ver}-fpm" "php${ver}-cli" "php${ver}-common" "php${ver}-mysql" "php${ver}-xml" "php${ver}-curl" "php${ver}-mbstring" "php${ver}-zip")
    local ext
    for ext in "$@"; do
        pkgs+=("php${ver}-${ext}")
    done

    mbf::system::pkg_install "${pkgs[@]}" || return 1
    mbf::system::service_ensure "php${ver}-fpm"
}

# Deploy or update a Git repository into `<app_dir>` and optionally run a build command
# Usage: mbf::webserver::deploy_git <app_dir> <repo_url> [branch] [build_cmd]
function mbf::webserver::deploy_git() {
    local app_dir="$1"
    local repo_url="$2"
    local branch="${3:-main}"
    local build_cmd="${4:-}"

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would deploy $repo_url ($branch) -> $app_dir"
        return 0
    fi

    if [ -d "${app_dir}/.git" ]; then
        mbf::exec::run git -C "$app_dir" fetch origin "$branch" || return 1
        mbf::exec::run git -C "$app_dir" checkout "$branch" || return 1
        mbf::exec::run git -C "$app_dir" pull --ff-only origin "$branch" || return 1
    else
        mkdir -p "$(dirname "$app_dir")"
        mbf::exec::run git clone -b "$branch" "$repo_url" "$app_dir" || return 1
    fi

    if [ -n "$build_cmd" ]; then
        (cd "$app_dir" && eval "$build_cmd")
    fi
}
