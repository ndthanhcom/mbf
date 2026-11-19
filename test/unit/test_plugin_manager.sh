#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use exec template
source "${MBF_HOME}/tools/plugin.sh"

function test_plugin_source_normalization_and_semver_compat() {
    assert_eq "https://github.com/ndthanhcom/mbf-linux-audit.git" \
        "$(_mbf_plugin_normalize_source "github.com/ndthanhcom/mbf-linux-audit")"
    assert_eq "https://github.com/ndthanhcom/mbf-linux-audit.git" \
        "$(_mbf_plugin_normalize_source "github.com/ndthanhcom/mbf-linux-audit/")"

    assert_eq "0" "$(_mbf_plugin_check_compat "1.0.0" ">=1.0.0 <=1.2.9" && echo 0 || echo 1)"
    assert_eq "0" "$(_mbf_plugin_check_compat "1.2.9" "v1.0.0 - v1.2.9" && echo 0 || echo 1)"
    assert_eq "1" "$(_mbf_plugin_check_compat "1.3.0" ">=1.0.0 <=1.2.9" && echo 0 || echo 1)"
    assert_eq "1" "$(_mbf_plugin_check_compat "0.9.9" ">=1.0.0 <=1.2.9" && echo 0 || echo 1)"
    assert_eq "0" "$(_mbf_plugin_check_compat "1.0.0" "1.0.0" && echo 0 || echo 1)"
}

function test_plugin_manifest_add_list_run_update_and_remove() {
    local work_dir data_dir repo_dir
    mbf::exec::tmpdir work_dir
    data_dir="${work_dir}/mbf_data"
    repo_dir="${work_dir}/sample-audit-repo"
    mkdir -p "${repo_dir}/plugins" "${repo_dir}/templates"

    export MBF_USER_DATA_DIR="$data_dir"
    export MBF_USER_PLUGINS_DIR="${data_dir}/plugins"

    cat <<'EOF' > "${repo_dir}/README.md"
# sample-audit

<!-- mbf:manifest:start -->
| Field | Value | Requirement |
| :--- | :--- | :--- |
| **name** | `sample-audit` | Mandatory |
| **version** | `1.0.0` | Mandatory |
| **mbf-compat** | `>=1.0.0 <=1.2.9` | Mandatory |
| **plugins** | `plugins/samplecheck.sh` | Mandatory |
| **requires** | `log`, `exec` | Mandatory |
| **mbf-api** | `1` | Optional |
| **scripts** | `run_audit.sh` | Optional |
| **templates** | `templates/` | Optional |
| **system-deps** | `awk` | Optional |
<!-- mbf:manifest:end -->
EOF

    cat <<'EOF' > "${repo_dir}/plugins/samplecheck.sh"
#!/usr/bin/env bash
# @mbf-module: samplecheck
# @mbf-api: 1
# mbf:requires log
function mbf::samplecheck::ping() {
    printf 'SAMPLECHECK_PONG\n'
}
EOF

    printf 'HELLO {{TARGET}}\n' > "${repo_dir}/templates/report.tpl"
    cat <<'EOF' > "${repo_dir}/run_audit.sh"
#!/usr/bin/env bash
printf 'AUDIT_SCRIPT_OK:%s\n' "${1:-none}"
EOF

    # 1. Install from local repo directory using README.md manifest
    mbf::plugin::add "$repo_dir" >/dev/null
    assert_file_exists "${data_dir}/.installed_plugins"
    assert_file_exists "${data_dir}/plugins/samplecheck.sh"
    assert_file_exists "${data_dir}/templates/report.tpl"
    assert_contains "$(cat "${data_dir}/.installed_plugins")" "sample-audit|1.0.0|"

    # 2. List & run extended script
    assert_contains "$(mbf::plugin::list)" "sample-audit"
    assert_eq "AUDIT_SCRIPT_OK:web01" "$(mbf::plugin::run "sample-audit" "run_audit.sh" "web01")"

    # 3. Verify template auto-discovery & plugin auto-discovery
    assert_contains "$(mbf::template::resolve "report.tpl")" "report.tpl"

    # 4. Update local repo package
    mbf::plugin::update "sample-audit" >/dev/null

    # 5. Clean removal deletes plugin, template, repo dir & registry entry
    mbf::plugin::remove "sample-audit" >/dev/null
    assert_eq "no" "$([ -f "${data_dir}/plugins/samplecheck.sh" ] && echo yes || echo no)"
    assert_eq "no" "$([ -f "${data_dir}/templates/report.tpl" ] && echo yes || echo no)"
    assert_eq "no" "$([ -d "${data_dir}/repos/sample-audit" ] && echo yes || echo no)"
    assert_not_contains "$(cat "${data_dir}/.installed_plugins")" "sample-audit|"

    # 6. Incompatible mbf-compat is rejected unless --force is passed
    local bad_repo="${work_dir}/future-repo"
    mkdir -p "${bad_repo}/plugins"
    cp "${repo_dir}/plugins/samplecheck.sh" "${bad_repo}/plugins/samplecheck.sh"
    cat <<'EOF' > "${bad_repo}/README.md"
<!-- mbf:manifest:start -->
| Field | Value |
| :--- | :--- |
| **name** | `future-pkg` |
| **version** | `2.0.0` |
| **mbf-compat** | `>=2.0.0 <=2.9.9` |
| **plugins** | `plugins/samplecheck.sh` |
| **requires** | `log` |
<!-- mbf:manifest:end -->
EOF
    local rc=0
    mbf::plugin::add "$bad_repo" >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "Incompatible mbf-compat must fail without --force"

    mbf::plugin::add "$bad_repo" --force >/dev/null 2>&1
    assert_file_exists "${data_dir}/plugins/samplecheck.sh"
    mbf::plugin::remove "future-pkg" >/dev/null

    unset MBF_USER_DATA_DIR MBF_USER_PLUGINS_DIR
}

run_test_suite "Manifest-Driven Plugin Manager (tools/plugin.sh)"
