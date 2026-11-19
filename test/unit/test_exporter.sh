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
    #    Includes a one-liner function to verify B21 regression fix!
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
    local url
    url="$(_mbf_varnish_build_url "$host")"
    mbf::log::info "Warming Varnish cache from $url"
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
    assert_contains "$doc_ext_out" "Detected mbf extension module: varnish"

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

run_test_suite "Smart Exporter & Doctor Diagnostics (exporter.sh, doctor.sh)"
