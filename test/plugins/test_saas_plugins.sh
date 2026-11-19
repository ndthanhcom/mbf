#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use webserver exec

function test_webserver_vhosts_via_templates_and_dryrun_remove() {
    local work_dir sites_dir docroot
    mbf::exec::tmpdir work_dir
    sites_dir="${work_dir}/nginx_sites"
    docroot="${work_dir}/www/blog.example.com"
    export MBF_NGINX_SITES_DIR="$sites_dir"

    mock_cmd "nginx" 0
    mock_cmd "systemctl" 0
    export MBF_ENV_TYPE_OVERRIDE="gitbash"
    mbf::webserver::ensure_nginx >/dev/null

    mbf::webserver::vhost_static "static.example.com" "$docroot"
    assert_file_exists "${sites_dir}/static.example.com.conf"

    mbf::webserver::vhost_proxy "jenkins.example.com" 8080
    assert_file_exists "${sites_dir}/jenkins.example.com.conf"
    assert_contains "$(cat "${sites_dir}/jenkins.example.com.conf")" "proxy_pass http://127.0.0.1:8080;"

    # Regression B14: vhost_remove in dry-run mode must NOT delete the file
    MBF_DRYRUN="1"
    mbf::webserver::vhost_remove "jenkins.example.com" >/dev/null
    assert_file_exists "${sites_dir}/jenkins.example.com.conf"
    MBF_DRYRUN="0"

    mbf::webserver::vhost_remove "jenkins.example.com"
    assert_eq "no" "$([ -f "${sites_dir}/jenkins.example.com.conf" ] && echo yes || echo no)"

    mbf::webserver::vhost_php "blog.example.com" "$docroot" "8.2"
    assert_file_exists "${sites_dir}/blog.example.com.conf"
    assert_contains "$(cat "${sites_dir}/blog.example.com.conf")" "php8.2-fpm.sock"
    unset MBF_ENV_TYPE_OVERRIDE
}

function test_webserver_ssl_php_and_git_deploy() {
    local work_dir app_dir
    mbf::exec::tmpdir work_dir
    app_dir="${work_dir}/app"

    if command -v openssl >/dev/null 2>&1; then
        mbf::webserver::ssl_self_signed "store.example.com" "$work_dir" 30
        assert_file_exists "${work_dir}/store.example.com.crt"
        assert_file_exists "${work_dir}/store.example.com.key"

        local days check_out
        days="$(mbf::webserver::ssl_expiry_days "${work_dir}/store.example.com.crt")"
        assert_ne "" "$days"
        check_out="$(mbf::webserver::ssl_check_renewals "$work_dir" 14)"
        assert_contains "$check_out" "Certificate"
    fi

    mock_cmd "certbot" 0
    mock_cmd "apt-get" 0
    mock_cmd "systemctl" 0
    mock_cmd "git" 0
    export MBF_PKG_MANAGER_OVERRIDE="apt-get"
    export MBF_ENV_TYPE_OVERRIDE="gitbash"

    mbf::webserver::ssl_letsencrypt "store.example.com" "ops@example.com" "/var/www/html" >/dev/null
    assert_called_with "certbot" "certonly --non-interactive --agree-tos -m ops@example.com"

    mbf::webserver::ensure_php "8.3" "intl" "bcmath" >/dev/null
    assert_called_with "apt-get" "php8.3-fpm"

    mkdir -p "$app_dir"
    mbf::webserver::deploy_git "$app_dir" "https://github.com/example/app.git" "main" -- touch "${app_dir}/built.flag" >/dev/null
    assert_called_with "git" "clone -b main https://github.com/example/app.git"
    assert_file_exists "${app_dir}/built.flag"
    unset MBF_PKG_MANAGER_OVERRIDE MBF_ENV_TYPE_OVERRIDE
}

run_test_suite "Plugin: Webserver (Nginx Templates, SSL, PHP & Git Deploy)"
