#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use exec template
source "${MBF_HOME}/tools/exporter.sh"
source "${MBF_HOME}/tools/doctor.sh"

function test_export_and_doctor_with_custom_extension_and_templates() {
    local work_dir
    mbf::exec::tmpdir work_dir
    local proj_dir="${work_dir}/m2_deployer"
    local bundle_dir="${work_dir}/dist_m2"
    mkdir -p "${proj_dir}/plugins" "${proj_dir}/templates"

    # 1. Create a strict compliant custom extension (`plugins/varnish.sh`)
    #    Includes a one-liner function (B21) AND a heredoc containing `}` at column 0!
    cat <<'EOF' > "${proj_dir}/plugins/varnish.sh"
#!/usr/bin/env bash
# @mbf-module: varnish
# mbf:requires log exec
function _mbf_varnish_one_liner() { printf 'sitemap.xml'; }
function _mbf_varnish_build_url() {
    printf 'http://%s/%s\n' "$1" "$(_mbf_varnish_one_liner)"
}
function mbf::varnish::warm() {
    local host="$1"
    local url vcl
    url="$(_mbf_varnish_build_url "$host")"
    vcl="$(cat <<'VCL_EOF'
backend default {
    .host = "127.0.0.1";
}
VCL_EOF
)"
    [ -n "$vcl" ] && mbf::log::info "Warming Varnish cache from $url"
}
function mbf::varnish::unused_purge() {
    echo "SHOULD_BE_TREE_SHAKEN"
}
EOF

    # 2. Create a custom project template (`templates/mftf.env.tpl`)
    cat <<'EOF' > "${proj_dir}/templates/mftf.env.tpl"
# @mbf-vars: MAGENTO_BASE_URL
MAGENTO_BASE_URL={{MAGENTO_BASE_URL}}
EOF

    # 3. Create main script using built-in + custom extension + custom template
    cat <<'EOF' > "${proj_dir}/warm_and_configure.sh"
#!/usr/bin/env bash
set -u
source "$(mbf --init)"
mbf::use args template varnish

mbf::args::option "d" "domain" "STORE_DOMAIN" "Store domain" "shop.example.com"
mbf::args::parse "$@"

OUT_ENV="${MBF_POSITIONAL_ARGS[0]}"
mbf::template::render "mftf.env.tpl" "$OUT_ENV" "MAGENTO_BASE_URL=https://${STORE_DOMAIN}/"
mbf::varnish::warm "$STORE_DOMAIN"
EOF

    # 4. Run `mbf::doctor::run` on both the custom extension and the main script
    local doc_ext_out doc_script_out
    doc_ext_out="$(MBF_EXT_PATH="${proj_dir}/plugins" mbf::doctor::run "${proj_dir}/plugins/varnish.sh")"
    assert_contains "$doc_ext_out" "Detected mbf library/plugin: varnish"

    doc_script_out="$(MBF_EXT_PATH="${proj_dir}/plugins" mbf::doctor::run "${proj_dir}/warm_and_configure.sh")"
    assert_contains "$doc_script_out" "mbf::use varnish"
    assert_contains "$doc_script_out" "Template mftf.env.tpl"

    # 5. Export as a bundle directory and verify tree-shaking + bundled custom templates
    MBF_EXT_PATH="${proj_dir}/plugins" mbf::exporter::run "${proj_dir}/warm_and_configure.sh" --bundle-dir "$bundle_dir"
    assert_file_exists "${bundle_dir}/warm_and_configure.sh"
    assert_file_exists "${bundle_dir}/templates/mftf.env.tpl"

    local exported_code
    exported_code="$(cat "${bundle_dir}/warm_and_configure.sh")"
    assert_contains "$exported_code" "# Standalone script exported by mbf v1.0.0 (Micro Bash Framework)"
    assert_contains "$exported_code" "function _mbf_varnish_one_liner()"
    assert_contains "$exported_code" "function mbf::varnish::warm()"
    assert_contains "$exported_code" "function _mbf_varnish_build_url()"
    assert_not_contains "$exported_code" "function mbf::varnish::unused_purge()"
    assert_not_contains "$exported_code" "mbf::check_update"
    assert_not_contains "$exported_code" "_mbf_version_gt"

    # 6. Execute exported bundle in an isolated environment (`env -i` with no MBF_HOME)
    local target_env="${work_dir}/rendered_mftf.env"
    local run_out
    run_out="$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" bash "${bundle_dir}/warm_and_configure.sh" --domain m2.ClientStore.com "$target_env" 2>&1)"
    assert_contains "$run_out" "Warming Varnish cache from http://m2.ClientStore.com/sitemap.xml"
    assert_contains "$(cat "$target_env")" "MAGENTO_BASE_URL=https://m2.ClientStore.com/"
}

function test_exporter_fails_on_unresolved_module_and_doctor_checks_naming() {
    local work_dir bad_ext bad_script
    mbf::exec::tmpdir work_dir
    bad_ext="${work_dir}/bad_plugin.sh"
    bad_script="${work_dir}/missing_mod.sh"

    cat <<'EOF' > "$bad_ext"
#!/usr/bin/env bash
# @mbf-module: magento
function invalid_function_name() {
    echo "bad"
}
EOF
    local rc=0
    mbf::doctor::run "$bad_ext" >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "Doctor should fail when extension function violates naming convention"

    # Regression B21: exporter must fail when an mbf::use module cannot be resolved
    cat <<'EOF' > "$bad_script"
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::use nonexistent_module_xyz
EOF
    rc=0
    mbf::exporter::run "$bad_script" -o "${work_dir}/out.sh" >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "Exporter should return 1 on unresolved mbf::use module"
}

function test_exporter_bundles_builtin_templates_and_keeps_version() {
    local work_dir proj_dir bundle_dir
    mbf::exec::tmpdir work_dir
    proj_dir="${work_dir}/tpl_proj"
    bundle_dir="${work_dir}/tpl_bundle"
    mkdir -p "$proj_dir"

    cat <<'EOF' > "${proj_dir}/scaffold_ext.sh"
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::use template
printf 'VER=%s\n' "$(mbf::version)"
mbf::template::render "script/extension.sh.tpl" "$1" "MODULE_NAME=demo" "MODULE_UPPER=DEMO"
EOF

    mbf::exporter::run "${proj_dir}/scaffold_ext.sh" --bundle-dir "$bundle_dir"
    assert_file_exists "${bundle_dir}/scaffold_ext.sh"
    assert_file_exists "${bundle_dir}/templates/script/extension.sh.tpl"
    assert_contains "$(cat "${bundle_dir}/scaffold_ext.sh")" "function mbf::version()"

    local out_ext="${work_dir}/demo.sh"
    local run_out
    run_out="$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" bash "${bundle_dir}/scaffold_ext.sh" "$out_ext")"
    assert_contains "$run_out" "VER=1.0.0"
    assert_file_exists "$out_ext"
    assert_contains "$(cat "$out_ext")" "# @mbf-module: demo"
}

function test_exporter_tree_shakes_new_primitives_and_runs_standalone() {
    local work_dir src_script out_script
    mbf::exec::tmpdir work_dir
    src_script="${work_dir}/ops_tool.sh"
    out_script="${work_dir}/ops_tool.standalone.sh"

    cat <<'EOF' > "$src_script"
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::strict
mbf::use str json net template

local_parts=()
mbf::str::split ", " "web01, web02" local_parts
printf 'SPLIT=%s:%s\n' "${#local_parts[@]}" "${local_parts[1]}"
printf 'MASK=%s\n' "$(mbf::str::mask "tok_1234567890" 4 4)"

arr="$(mbf::json::array_raw '{"id":1}' '{"id":2}')"
printf 'ARR=%s\n' "$arr"
printf 'DEF=%s\n' "$(mbf::json::get "$arr" "missing" "fallback")"
mbf::json::has '{"ok":true}' "ok" && printf 'HAS=yes\n'

printf 'QS=%s\n' "$(mbf::net::build_query "env=prod" "q=a b")"
MBF_DRYRUN=1 mbf::net::fetch "GET" "https://api.example.com/health" >/dev/null 2>&1
printf 'FETCH=%s\n' "$MBF_HTTP_LAST_STATUS"

printf 'TPL=%s\n' "$(mbf::template::render_str '{{HOST:-localhost}}:{{PORT:-8080}}' 'PORT=9090')"
EOF

    mbf::exporter::run "$src_script" -o "$out_script"
    assert_file_exists "$out_script"

    local exported_code
    exported_code="$(cat "$out_script")"
    assert_contains "$exported_code" "function _mbf_template_lookup_var()"
    assert_contains "$exported_code" "MBF_HTTP_LAST_STATUS="
    assert_not_contains "$exported_code" "function mbf::net::resolve_dns()"
    assert_not_contains "$exported_code" "function mbf::str::hmac_sha256()"

    local run_out
    run_out="$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" bash "$out_script" 2>&1)"
    assert_contains "$run_out" "SPLIT=2:web02"
    assert_contains "$run_out" "MASK=tok_******7890"
    assert_contains "$run_out" 'ARR=[{"id":1},{"id":2}]'
    assert_contains "$run_out" "DEF=fallback"
    assert_contains "$run_out" "HAS=yes"
    assert_contains "$run_out" "QS=env=prod&q=a%20b"
    assert_contains "$run_out" "FETCH=200"
    assert_contains "$run_out" "TPL=localhost:9090"
}

function test_exporter_bash_guard_recursive_source_and_mbf_init() {
    local work_dir proj_dir out_script
    mbf::exec::tmpdir work_dir
    proj_dir="${work_dir}/nested_proj"
    out_script="${work_dir}/nested_standalone.sh"
    mkdir -p "${proj_dir}/helpers"

    cat <<'EOF' > "${proj_dir}/helpers/level2.sh"
#!/usr/bin/env bash
mbf::use str
function _nested_slug() {
    mbf::str::slugify "$1"
}
EOF

    cat <<'EOF' > "${proj_dir}/helpers/level1.sh"
#!/usr/bin/env bash
source "level2.sh"
EOF

    cat <<'EOF' > "${proj_dir}/app.sh"
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::strict
mbf::init
source "helpers/level1.sh"
printf 'NESTED=%s\n' "$(_nested_slug "Hello World!")"
EOF

    mbf::exporter::run "${proj_dir}/app.sh" -o "$out_script"
    assert_file_exists "$out_script"

    # 1. Exported script enforces Bash >= 4.3 guard
    local b3_out b3_rc=0
    b3_out="$(MBF_BASH_MAJOR_OVERRIDE=3 MBF_BASH_MINOR_OVERRIDE=2 bash "$out_script" 2>&1)" || b3_rc=$?
    assert_eq "1" "$b3_rc" "Exported script must reject Bash < 4.3"
    assert_contains "$b3_out" "Bash >= 4.3 is required"

    # 2. Recursive source inlining + mbf::init (with MBF_SUDO=1) run cleanly in isolated env
    mock_cmd "sudo" 0
    local run_out
    run_out="$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" MBF_SUDO=1 bash "$out_script" 2>&1)"
    assert_contains "$run_out" "NESTED=hello-world"
}

run_test_suite "Smart Exporter & Doctor Diagnostics (exporter.sh, doctor.sh)"
