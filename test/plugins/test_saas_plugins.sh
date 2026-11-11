#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use webserver database exec

function test_webserver_vhosts_via_templates_and_wordpress_stack() {
    local work_dir sites_dir docroot
    mbf::exec::tmpdir work_dir
    sites_dir="${work_dir}/nginx_sites"
    docroot="${work_dir}/www/blog.example.com"
    export MBF_NGINX_SITES_DIR="$sites_dir"

    mbf::webserver::vhost_proxy "jenkins.example.com" 8080
    assert_file_exists "${sites_dir}/jenkins.example.com.conf"
    assert_contains "$(cat "${sites_dir}/jenkins.example.com.conf")" "proxy_pass http://127.0.0.1:8080;"

    mbf::webserver::vhost_remove "jenkins.example.com"
    assert_eq "no" "$([ -f "${sites_dir}/jenkins.example.com.conf" ] && echo yes || echo no)"

    mbf::webserver::vhost_php "blog.example.com" "$docroot" "8.2"
    assert_file_exists "${sites_dir}/blog.example.com.conf"
    assert_contains "$(cat "${sites_dir}/blog.example.com.conf")" "php8.2-fpm.sock"
}

function test_webserver_ssl_self_signed_and_renewal_check() {
    local work_dir
    mbf::exec::tmpdir work_dir

    if command -v openssl >/dev/null 2>&1; then
        mbf::webserver::ssl_self_signed "store.example.com" "$work_dir" 30
        assert_file_exists "${work_dir}/store.example.com.crt"
        assert_file_exists "${work_dir}/store.example.com.key"

        local check_out
        check_out="$(mbf::webserver::ssl_check_renewals "$work_dir" 14)"
        assert_eq "0" "$?"
        assert_contains "$check_out" "Certificate"
    fi
}

run_test_suite "Plugin: Webserver (Nginx Templates, SSL & App Stacks)"
