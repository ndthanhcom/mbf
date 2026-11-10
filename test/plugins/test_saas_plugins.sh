#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use webserver ssl database appstack docker agent fs

function test_webserver_vhosts_and_wordpress_stack() {
    local work_dir sites_dir docroot
    mbf::fs::tmpdir work_dir
    sites_dir="${work_dir}/nginx_sites"
    docroot="${work_dir}/www/blog.example.com"
    export MBF_NGINX_SITES_DIR="$sites_dir"

    mbf::webserver::vhost_proxy "api.example.com" 4000
    assert_file_exists "${sites_dir}/api.example.com.conf"
    assert_contains "$(cat "${sites_dir}/api.example.com.conf")" "proxy_pass http://127.0.0.1:4000;"

    mbf::webserver::vhost_remove "api.example.com"
    assert_eq "no" "$([ -f "${sites_dir}/api.example.com.conf" ] && echo yes || echo no)"

    # Provision WordPress stack (dry-run DB creation, real vhost & wp-config.php)
    MBF_DRYRUN="1"
    mbf::database::create_db_and_user "mysql" "wp_db" "wp_user" "secret" >/dev/null
    MBF_DRYRUN="0"

    mbf::webserver::vhost_php "blog.example.com" "$docroot" "8.2"
    assert_file_exists "${sites_dir}/blog.example.com.conf"
    assert_contains "$(cat "${sites_dir}/blog.example.com.conf")" "php8.2-fpm.sock"
}

function test_ssl_self_signed_and_renewal_check() {
    local work_dir
    mbf::fs::tmpdir work_dir

    if command -v openssl >/dev/null 2>&1; then
        mbf::ssl::issue_self_signed "test.example.com" "$work_dir" 30
        assert_file_exists "${work_dir}/test.example.com.crt"
        assert_file_exists "${work_dir}/test.example.com.key"

        local check_out
        check_out="$(mbf::ssl::check_renewals "$work_dir" 14)"
        assert_eq "0" "$?"
        assert_contains "$check_out" "Certificate"
    fi
}

function test_docker_and_saas_agent_plugins() {
    local work_dir sshd_conf
    mbf::fs::tmpdir work_dir
    sshd_conf="${work_dir}/sshd_config"
    printf 'PermitRootLogin no\nPasswordAuthentication no\n' > "$sshd_conf"

    local review_json
    review_json="$(mbf::agent::collect_review_json "$sshd_conf")"
    assert_eq "no" "$(mbf::json::get "$review_json" "ssh_permit_root_login")"
    assert_eq "no" "$(mbf::json::get "$review_json" "ssh_password_auth")"

    MBF_DRYRUN="1"
    export MBF_SAAS_WEBHOOK_URL="https://saas.example.com/api/webhook"
    export MBF_SAAS_SECRET="super_secret_key"
    local evt_out
    evt_out="$(mbf::agent::send_event "job_99" "provision_nginx" "completed" "Nginx ready")"
    assert_contains "$evt_out" "Would HTTP POST https://saas.example.com/api/webhook"
    assert_contains "$evt_out" '"job_id":"job_99"'

    printf 'version: "3"\n' > "${work_dir}/docker-compose.yml"
    local dkr_out
    dkr_out="$(mbf::docker::compose_up "$work_dir")"
    assert_contains "$dkr_out" "Would run docker compose up -d"
}

run_test_suite "Plugins: Webserver, SSL, Database, Appstack, Docker & SaaS Agent"
