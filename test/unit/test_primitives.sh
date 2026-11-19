#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use template json str net exec

function test_template_convention_ampersands_and_custom_override() {
    local work_dir ext_out resolved_tpl tpl_list
    mbf::exec::tmpdir work_dir
    ext_out="${work_dir}/mycache.sh"

    resolved_tpl="$(mbf::template::resolve "script/extension.sh.tpl")"
    assert_file_exists "$resolved_tpl"
    mbf::template::render "script/extension.sh.tpl" "$ext_out" \
        "MODULE_NAME=mycache" \
        "MODULE_UPPER=MYCACHE"

    assert_file_exists "$ext_out"
    assert_contains "$(cat "$ext_out")" "# @mbf-module: mycache"
    assert_contains "$(cat "$ext_out")" "MBF_MYCACHE_DEFAULT"

    # Regression B4: `&` and `\` in variable values must not be corrupted by Bash 5.2 patsub_replacement
    local rendered_str
    rendered_str="$(mbf::template::render_str 'DSN={{DSN}}' 'DSN=mysql://u:p&1@db/m2?a=1&b=2')"
    assert_eq 'DSN=mysql://u:p&1@db/m2?a=1&b=2' "$rendered_str"

    mkdir -p "${work_dir}/templates/app"
    cat <<'EOF' > "${work_dir}/templates/app/service.conf.tpl"
# @mbf-vars: DOMAIN PORT
server_name {{DOMAIN}};
listen {{PORT}};
EOF
    local conf_out="${work_dir}/service.conf"
    MBF_TEMPLATE_PATH="${work_dir}/templates" mbf::template::validate_vars "app/service.conf.tpl" "DOMAIN=m2.example.com" "PORT=8080"
    MBF_TEMPLATE_PATH="${work_dir}/templates" mbf::template::render "app/service.conf.tpl" "$conf_out" \
        "DOMAIN=m2.example.com" \
        "PORT=8080"

    assert_contains "$(cat "$conf_out")" "server_name m2.example.com;"
    assert_contains "$(cat "$conf_out")" "listen 8080;"
    assert_not_contains "$(cat "$conf_out")" "@mbf-vars"

    local rc=0
    MBF_TEMPLATE_PATH="${work_dir}/templates" mbf::template::render "app/service.conf.tpl" "$conf_out" "DOMAIN=m2.example.com" >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc"

    printf 'atomic_payload\n' | mbf::template::write_atomic "${work_dir}/atomic.txt"
    assert_eq "atomic_payload" "$(cat "${work_dir}/atomic.txt")"

    tpl_list="$(MBF_TEMPLATE_PATH="${work_dir}/templates" mbf::template::list)"
    assert_contains "$tpl_list" "app/service.conf.tpl"
    assert_contains "$tpl_list" "script/extension.sh.tpl"
}

function test_json_builder_and_parser_with_escapes_and_colons() {
    local obj arr esc
    esc="$(mbf::json::escape $'line1\n"quoted"\\path')"
    assert_contains "$esc" '\n\"quoted\"\\path'

    # Regression B3: `:=` inside a string value (`url=http://x/?a:=b`) must stay a string
    obj="$(mbf::json::object "job_id=deploy_42" 'msg=Reloaded "nginx", status: ok' 'url=https://shop.example.com/?filter:=active' "workers:=4" "varnish_enabled:=true")"
    assert_eq "deploy_42" "$(mbf::json::get "$obj" "job_id")"
    assert_eq 'Reloaded "nginx", status: ok' "$(mbf::json::get "$obj" "msg")"
    assert_eq 'https://shop.example.com/?filter:=active' "$(mbf::json::get "$obj" "url")"
    assert_eq "4" "$(mbf::json::get "$obj" "workers")"
    assert_eq "true" "$(mbf::json::get "$obj" "varnish_enabled")"

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

    if command -v openssl >/dev/null 2>&1; then
        hmac="$(mbf::str::hmac_sha256 "saas_webhook_secret" "job_42:completed")"
        assert_eq "64" "${#hmac}"
    fi
}

function test_net_http_client_atomic_download_and_ports() {
    local work_dir dl_file expected_sha
    mbf::exec::tmpdir work_dir
    dl_file="${work_dir}/artifact.bin"

    mock_cmd "curl" 0 "DOWNLOADED_BINARY_PAYLOAD"
    mbf::net::header_add "Authorization: Bearer test-token-123"
    local req_out
    req_out="$(mbf::net::request "PUT" "https://api.example.com/v1/nodes" '{"active":true}')"
    assert_eq "DOWNLOADED_BINARY_PAYLOAD" "$req_out"
    assert_called_with "curl" "-X PUT"
    assert_called_with "curl" "-H Authorization: Bearer test-token-123"
    mbf::net::headers_clear

    # Mock curl -o download and verify atomic SHA-256 check
    cat <<'EOF' > "${MBF_MOCK_BIN}/curl"
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do
    if [ "$1" == "-o" ]; then out="$2"; shift 2; else shift 1; fi
done
[ -n "$out" ] && printf 'VERIFIED_CONTENT\n' > "$out"
exit 0
EOF
    chmod +x "${MBF_MOCK_BIN}/curl"

    mbf::net::download "https://example.com/artifact.bin" "$dl_file"
    assert_file_exists "$dl_file"
    expected_sha="$(mbf::str::sha256 "$dl_file")"
    mbf::net::download "https://example.com/artifact.bin" "$dl_file" "$expected_sha"

    # Regression B16: mismatched SHA-256 must fail and remove the temporary file
    local bad_dest="${work_dir}/corrupt.bin" rc=0
    mbf::net::download "https://example.com/artifact.bin" "$bad_dest" "0000000000000000000000000000000000000000000000000000000000000000" 2>/dev/null || rc=$?
    assert_eq "1" "$rc"
    assert_eq "no" "$([ -f "$bad_dest" ] && echo yes || echo no)"

    mock_cmd "nc" 0
    mbf::net::is_port_open 6379 "127.0.0.1"
    mbf::net::wait_port 6379 "127.0.0.1" 2

    mock_cmd "getent" 0 "93.184.216.34 STREAM example.com"
    assert_eq "93.184.216.34" "$(mbf::net::resolve_dns "example.com")"
    assert_ne "" "$(mbf::net::private_ip)"

    MBF_DRYRUN="1"
    assert_eq "203.0.113.10" "$(mbf::net::public_ip)"
    assert_eq "200" "$(mbf::net::status_code "https://shop.example.com/health_check.php")"
    mbf::net::wait_http "https://shop.example.com/health_check.php" 5 200 >/dev/null
    MBF_DRYRUN="0"
}

run_test_suite "Core Libraries: template, json, str & net"
