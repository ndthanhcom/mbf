#!/usr/bin/env bash
# mbf:requires log exec os service user webserver database
# ==============================================================================
# mbf plugin: appstack
# Website & Application Stack Provisioner (PHP-FPM, Git Deploy, WordPress)
# ==============================================================================

# Ensure PHP-FPM and common extensions are installed for the given version
# Usage: mbf::appstack::ensure_php [php_version] [extra_exts...]
function mbf::appstack::ensure_php() {
    local ver="${1:-8.2}"
    shift 1 2>/dev/null || true

    local -a pkgs=("php${ver}-fpm" "php${ver}-cli" "php${ver}-common" "php${ver}-mysql" "php${ver}-xml" "php${ver}-curl" "php${ver}-mbstring" "php${ver}-zip")
    local ext
    for ext in "$@"; do
        pkgs+=("php${ver}-${ext}")
    done

    mbf::os::pkg_install "${pkgs[@]}" || return 1
    mbf::service::ensure_running "php${ver}-fpm"
}

# Deploy or update a Git repository into `<app_dir>` and optionally run a build command
# Usage: mbf::appstack::deploy_git <app_dir> <repo_url> [branch] [build_cmd]
function mbf::appstack::deploy_git() {
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

# Provision a complete WordPress site (Nginx vhost + database + wp-config.php)
# Usage: mbf::appstack::install_wordpress <domain> <root_dir> <db_name> <db_user> <db_pass> [php_ver]
function mbf::appstack::install_wordpress() {
    local domain="$1"
    local root_dir="$2"
    local db_name="$3"
    local db_user="$4"
    local db_pass="$5"
    local php_ver="${6:-8.2}"

    mbf::database::create_db_and_user "mysql" "$db_name" "$db_user" "$db_pass" || return 1
    mbf::webserver::vhost_php "$domain" "$root_dir" "$php_ver" || return 1

    mkdir -p "$root_dir"
    if [ ! -f "${root_dir}/wp-config.php" ]; then
        cat <<EOF | mbf::template::write_atomic "${root_dir}/wp-config.php"
<?php
define( 'DB_NAME', '${db_name}' );
define( 'DB_USER', '${db_user}' );
define( 'DB_PASSWORD', '${db_pass}' );
define( 'DB_HOST', 'localhost' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );
\$table_prefix = 'wp_';
define( 'WP_DEBUG', false );
if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOF
    fi
    mbf::log::ok "WordPress stack provisioned for $domain at $root_dir"
}
