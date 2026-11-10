#!/usr/bin/env bash
# mbf:requires log exec os service template
# ==============================================================================
# mbf plugin: webserver
# Automated Nginx Vhost Provisioner (Static, PHP-FPM, Reverse Proxy)
# ==============================================================================

# mbf:state_start
MBF_NGINX_SITES_DIR="${MBF_NGINX_SITES_DIR:-/etc/nginx/conf.d}"
# mbf:state_end

# Ensure Nginx is installed and running
function mbf::webserver::ensure_nginx() {
    if ! command -v nginx >/dev/null 2>&1; then
        mbf::os::pkg_install nginx || return 1
    fi
    mbf::service::ensure_running nginx
}

function _mbf_nginx_validate_and_reload() {
    local conf_file="$1"
    if mbf::is_dryrun; then
        return 0
    fi
    if command -v nginx >/dev/null 2>&1 && [ "$MBF_NGINX_SITES_DIR" == "/etc/nginx/conf.d" ]; then
        if ! nginx -t 2>/dev/null; then
            mbf::log::error "Nginx config test failed for $conf_file; removing invalid config"
            rm -f "$conf_file"
            return 1
        fi
        mbf::service::reload nginx
    fi
    return 0
}

# Create a static site Nginx virtual host
# Usage: mbf::webserver::vhost_static <domain> <root_dir>
function mbf::webserver::vhost_static() {
    local domain="$1"
    local root_dir="$2"
    local conf_file="${MBF_NGINX_SITES_DIR}/${domain}.conf"

    mkdir -p "$MBF_NGINX_SITES_DIR" "$root_dir" 2>/dev/null || true
    cat <<EOF | mbf::template::write_atomic "$conf_file"
server {
    listen 80;
    server_name ${domain} www.${domain};
    root ${root_dir};
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    _mbf_nginx_validate_and_reload "$conf_file"
}

# Create a PHP-FPM site Nginx virtual host
# Usage: mbf::webserver::vhost_php <domain> <root_dir> [php_version]
function mbf::webserver::vhost_php() {
    local domain="$1"
    local root_dir="$2"
    local php_ver="${3:-8.2}"
    local conf_file="${MBF_NGINX_SITES_DIR}/${domain}.conf"

    mkdir -p "$MBF_NGINX_SITES_DIR" "$root_dir" 2>/dev/null || true
    cat <<EOF | mbf::template::write_atomic "$conf_file"
server {
    listen 80;
    server_name ${domain} www.${domain};
    root ${root_dir};
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php${php_ver}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF
    _mbf_nginx_validate_and_reload "$conf_file"
}

# Create a reverse-proxy Nginx virtual host (for Node.js, Python, Docker apps)
# Usage: mbf::webserver::vhost_proxy <domain> <upstream_port>
function mbf::webserver::vhost_proxy() {
    local domain="$1"
    local port="$2"
    local conf_file="${MBF_NGINX_SITES_DIR}/${domain}.conf"

    mkdir -p "$MBF_NGINX_SITES_DIR" 2>/dev/null || true
    cat <<EOF | mbf::template::write_atomic "$conf_file"
server {
    listen 80;
    server_name ${domain} www.${domain};

    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    _mbf_nginx_validate_and_reload "$conf_file"
}

# Remove an Nginx virtual host
function mbf::webserver::vhost_remove() {
    local domain="$1"
    local conf_file="${MBF_NGINX_SITES_DIR}/${domain}.conf"
    rm -f "$conf_file"
    mbf::is_dryrun || _mbf_nginx_validate_and_reload "$conf_file"
}
