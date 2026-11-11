#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use template json str net exec

function test_template_convention_builtin_and_custom_override() {
    local work_dir vhost_out
    mbf::exec::tmpdir work_dir
    vhost_out="${work_dir}/shop.example.com.conf"

    # 1. Render built-in nginx/vhost-php.conf.tpl
    mbf::template::render "nginx/vhost-php.conf.tpl" "$vhost_out" \
        "DOMAIN=shop.example.com" \
        "ROOT_DIR=/var/www/magento2/pub" \
        "PHP_VERSION=8.3"

    assert_file_exists "$vhost_out"
    assert_contains "$(cat "$vhost_out")" "server_name shop.example.com www.shop.example.com;"
    assert_contains "$(cat "$vhost_out")" "fastcgi_pass unix:/run/php/php8.3-fpm.sock;"
    assert_not_contains "$(cat "$vhost_out")" "@mbf-vars"

    # 2. Missing required # @mbf-vars variable should fail validation
    mbf::template::render "nginx/vhost-php.conf.tpl" "$vhost_out" "DOMAIN=shop.example.com" >/dev/null 2>&1
    assert_eq "1" "$?"

    # 3. Custom script template override via MBF_TEMPLATE_PATH
    mkdir -p "${work_dir}/templates/nginx"
    cat <<'EOF' > "${work_dir}/templates/nginx/vhost-php.conf.tpl"
# @mbf-vars: DOMAIN ROOT_DIR PHP_VERSION
# Custom Magento 2 Varnish + PHP-FPM Vhost Override
server {
    server_name {{DOMAIN}};
    root {{ROOT_DIR}};
    set $MAGE_PHP {{PHP_VERSION}};
}
EOF
    MBF_TEMPLATE_PATH="${work_dir}/templates" mbf::template::render "nginx/vhost-php.conf.tpl" "$vhost_out" \
        "DOMAIN=m2.example.com" \
        "ROOT_DIR=/var/www/m2/pub" \
        "PHP_VERSION=8.2"

    assert_contains "$(cat "$vhost_out")" "# Custom Magento 2 Varnish + PHP-FPM Vhost Override"
    assert_contains "$(cat "$vhost_out")" "set \$MAGE_PHP 8.2;"
}

function test_json_builder_and_parser_for_saas_payloads() {
    local obj arr
    obj="$(mbf::json::object "job_id=deploy_42" "workers:=4" "varnish_enabled:=true")"
    assert_eq '{"job_id":"deploy_42","workers":4,"varnish_enabled":true}' "$obj"
    assert_eq "deploy_42" "$(mbf::json::get "$obj" "job_id")"
    assert_eq "4" "$(mbf::json::get "$obj" "workers")"

    arr="$(mbf::json::array "nginx" "php8.2-fpm" "varnish" "opensearch")"
    assert_eq '["nginx","php8.2-fpm","varnish","opensearch"]' "$arr"
}

function test_str_slugify_random_and_sha256_hmac() {
    local work_dir release_tar hash hmac
    mbf::exec::tmpdir work_dir
    release_tar="${work_dir}/release-2026.tar.gz"
    printf 'magento2-build-artifact\n' > "$release_tar"

    assert_eq "magento-2-storefront" "$(mbf::str::trim "   magento-2-storefront   ")"
    assert_eq "client-store-prod-01" "$(mbf::str::slugify "Client Store (Prod #01)!")"

    local db_pass
    db_pass="$(mbf::str::random 24)"
    assert_eq "24" "${#db_pass}"

    hash="$(mbf::str::sha256 "$release_tar")"
    assert_eq "64" "${#hash}"
    mbf::str::verify_sha256 "$release_tar" "$hash"
    assert_eq "0" "$?"

    if command -v openssl >/dev/null 2>&1; then
        hmac="$(mbf::str::hmac_sha256 "saas_webhook_secret" "job_42:completed")"
        assert_eq "64" "${#hmac}"
    fi
}

function test_net_http_client_and_readiness_dryrun() {
    MBF_DRYRUN="1"
    local out
    out="$(mbf::net::post_json "https://jenkins.example.com/job/m2-build/build" '{"branch":"main"}')"
    assert_contains "$out" "Would HTTP POST https://jenkins.example.com/job/m2-build/build"
    assert_eq "200" "$(mbf::net::status_code "https://shop.example.com/health_check.php")"
    mbf::net::wait_http "https://shop.example.com/health_check.php" 5 200 >/dev/null
    assert_eq "0" "$?"
}

run_test_suite "Core Libraries: template, json, str & net"
