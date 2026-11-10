#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use str json http template lock fs

function test_str_manipulation_and_validation() {
    assert_eq "hello world" "$(mbf::str::trim "   hello world   ")"
    assert_eq "hello" "$(mbf::str::lower "HeLLo")"
    assert_eq "HELLO" "$(mbf::str::upper "HeLLo")"
    assert_eq "my-saas-site-01" "$(mbf::str::slugify "My SaaS Site #01!")"

    assert_eq "0" "$(mbf::str::is_alnum "user_01" && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::str::is_alnum "user-01!" && echo 0 || echo 1)"

    assert_eq "0" "$(mbf::str::is_domain "app.example.com" && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::str::is_domain "not_a_domain" && echo 0 || echo 1)"

    assert_eq "0" "$(mbf::str::is_ip "192.168.1.10" && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::str::is_ip "999.168.1.10" && echo 0 || echo 1)"

    assert_eq "0" "$(mbf::str::is_email "ops@example.com" && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::str::is_email "ops@invalid" && echo 0 || echo 1)"

    local tok
    tok="$(mbf::str::random 32)"
    assert_eq "32" "${#tok}"
}

function test_json_builder_and_parser() {
    local obj arr
    obj="$(mbf::json::object "host=web01" "cores:=8" "active:=true")"
    assert_eq '{"host":"web01","cores":8,"active":true}' "$obj"
    assert_eq "web01" "$(mbf::json::get "$obj" "host")"
    assert_eq "8" "$(mbf::json::get "$obj" "cores")"

    arr="$(mbf::json::array "nginx" "mysql" "redis")"
    assert_eq '["nginx","mysql","redis"]' "$arr"
}

function test_http_client_dryrun() {
    MBF_DRYRUN="1"
    local out
    out="$(mbf::http::post_json "https://api.example.com/events" '{"ok":true}')"
    assert_contains "$out" "Would HTTP POST https://api.example.com/events"
    assert_eq "200" "$(mbf::http::status_code "https://api.example.com/health")"
    mbf::http::wait_ok "https://api.example.com/health" 5 200 >/dev/null
    assert_eq "0" "$?"
}

function test_template_render_and_backup_rollback() {
    local work_dir tpl dest
    mbf::fs::tmpdir work_dir
    tpl="${work_dir}/vhost.tpl"
    dest="${work_dir}/vhost.conf"

    printf 'server_name {{DOMAIN}};\nlisten {{PORT}};\n' > "$tpl"
    PORT="8080" mbf::template::render "$tpl" "$dest" "DOMAIN=app.example.com"
    assert_file_exists "$dest"
    assert_contains "$(cat "$dest")" "server_name app.example.com;"
    assert_contains "$(cat "$dest")" "listen 8080;"

    mbf::template::backup "$dest"
    printf 'corrupted_config\n' > "$dest"
    mbf::template::rollback "$dest" 2>/dev/null
    assert_contains "$(cat "$dest")" "server_name app.example.com;"
}

function test_lock_concurrency_and_step_state() {
    local work_dir
    mbf::fs::tmpdir work_dir
    MBF_LOCK_DIR="$work_dir"
    MBF_STATE_FILE="${work_dir}/steps.state"

    mbf::lock::acquire "deploy_job" 0
    assert_eq "0" "$?"

    # Second acquire with live PID should fail immediately when timeout=0
    mbf::lock::acquire "deploy_job" 0 >/dev/null 2>&1
    assert_eq "1" "$?"

    mbf::lock::release "deploy_job"
    mbf::lock::acquire "deploy_job" 0
    assert_eq "0" "$?"
    mbf::lock::release "deploy_job"

    # Idempotent step checkpointing
    local count_file="${work_dir}/counter"
    printf '0\n' > "$count_file"
    function _inc_step() {
        local c
        c="$(cat "$count_file")"
        printf '%d\n' $((c + 1)) > "$count_file"
    }

    mbf::lock::step_run "step_01_init" _inc_step >/dev/null
    mbf::lock::step_run "step_01_init" _inc_step >/dev/null
    assert_eq "1" "$(cat "$count_file")" "Completed step should only execute once"
}

run_test_suite "Core Primitives: str, json, http, template & lock"
