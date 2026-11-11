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
    cat <<'EOF' > "${proj_dir}/plugins/varnish.sh"
#!/usr/bin/env bash
# @mbf-module: varnish
# @mbf-rank: ••
# mbf:requires log exec
function _mbf_varnish_build_url() {
    printf 'http://%s/sitemap.xml\n' "$1"
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
    assert_eq "0" "$?"
    assert_contains "$doc_ext_out" "Detected mbf extension module: varnish"

    doc_script_out="$(MBF_EXT_PATH="${proj_dir}/plugins" mbf::doctor::run "${proj_dir}/warm_and_configure.sh")"
    assert_eq "0" "$?"
    assert_contains "$doc_script_out" "mbf::use varnish"
    assert_contains "$doc_script_out" "Template mftf.env.tpl"

    # 5. Export as a bundle directory and verify tree-shaking + bundled custom templates
    MBF_EXT_PATH="${proj_dir}/plugins" mbf::exporter::run "${proj_dir}/warm_and_configure.sh" --bundle-dir "$bundle_dir"
    assert_file_exists "${bundle_dir}/warm_and_configure.sh"
    assert_file_exists "${bundle_dir}/templates/mftf.env.tpl"

    local exported_code
    exported_code="$(cat "${bundle_dir}/warm_and_configure.sh")"
    assert_contains "$exported_code" "function mbf::varnish::warm()"
    assert_contains "$exported_code" "function _mbf_varnish_build_url()"
    assert_not_contains "$exported_code" "function mbf::varnish::unused_purge()"

    # 6. Execute exported bundle with MBF_HOME=/nonexistent
    local target_env="${work_dir}/rendered_mftf.env"
    local run_out
    run_out="$(MBF_HOME="/nonexistent" bash "${bundle_dir}/warm_and_configure.sh" --domain m2.ClientStore.com "$target_env")"
    assert_contains "$run_out" "Warming Varnish cache from http://m2.ClientStore.com/sitemap.xml"
    assert_contains "$(cat "$target_env")" "MAGENTO_BASE_URL=https://m2.ClientStore.com/"
}

function test_doctor_detects_invalid_extension_naming() {
    local work_dir bad_ext
    mbf::exec::tmpdir work_dir
    bad_ext="${work_dir}/bad_plugin.sh"
    cat <<'EOF' > "$bad_ext"
#!/usr/bin/env bash
# @mbf-module: magento
function invalid_function_name() {
    echo "bad"
}
EOF
    mbf::doctor::run "$bad_ext" >/dev/null 2>&1
    assert_eq "1" "$?" "Doctor should fail when extension function violates naming convention"
}

run_test_suite "Smart Exporter & Doctor Diagnostics (exporter.sh, doctor.sh)"
