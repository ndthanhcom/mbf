#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use exec

function test_cli_init_version_help_and_list() {
    local mbf_bin="${MBF_HOME}/bin/mbf"
    local init_path ver_out help_out list_out

    init_path="$(bash "$mbf_bin" --init)"
    assert_eq "${MBF_HOME}/framework.sh" "$init_path"

    ver_out="$(bash "$mbf_bin" --version)"
    assert_contains "$ver_out" "mbf v1.0.0"
    assert_contains "$(bash "$mbf_bin" version)" "mbf v1.0.0"

    help_out="$(bash "$mbf_bin" --help)"
    assert_contains "$help_out" "mbf — Micro Bash Framework CLI"
    assert_contains "$help_out" "mbf export"

    list_out="$(bash "$mbf_bin" list)"
    assert_contains "$list_out" "Core Libraries"
    assert_contains "$list_out" "Plugins"
    assert_contains "$list_out" "mbf::exec::run"

    local rc=0
    bash "$mbf_bin" unknown-subcmd >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "Unknown CLI command should return non-zero"
}

function test_cli_new_doctor_and_export_e2e() {
    local mbf_bin="${MBF_HOME}/bin/mbf"
    local work_dir new_script new_ext exported_out
    mbf::exec::tmpdir work_dir
    new_script="${work_dir}/deploy.sh"
    new_ext="${work_dir}/plugins/customops.sh"
    exported_out="${work_dir}/dist/deploy.sh"

    mkdir -p "${work_dir}/plugins"

    # Scaffold standard script and verify production-safe defaults
    bash "$mbf_bin" new "$new_script" >/dev/null
    assert_file_exists "$new_script"
    local script_content
    script_content="$(cat "$new_script")"
    assert_contains "$script_content" 'source "$(mbf --init)"'
    assert_contains "$script_content" "mbf::strict"
    assert_contains "$script_content" "MBF_DRYRUN"

    # Refuses to overwrite existing script
    local rc=0
    bash "$mbf_bin" new "$new_script" >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc"

    # Scaffold custom extension and validate with `mbf doctor`
    bash "$mbf_bin" new --ext "$new_ext" >/dev/null
    assert_file_exists "$new_ext"
    local doc_out
    doc_out="$(bash "$mbf_bin" doctor "$new_ext")"
    assert_contains "$doc_out" "Detected mbf extension module: customops"
    assert_contains "$doc_out" "0 error(s), 0 warning(s)"

    # Export scaffolded script and run it in a clean environment (`env -i`)
    bash "$mbf_bin" export "$new_script" -o "$exported_out" >/dev/null
    assert_file_exists "$exported_out"
    local run_out
    run_out="$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" bash "$exported_out" --dry-run 2>&1)"
    assert_contains "$run_out" "Starting deploy.sh..."

    # Test `mbf remote` agentless execution via local-passthrough ssh mock
    cat <<EOF > "${MBF_MOCK_BIN}/ssh"
#!/usr/bin/env bash
printf 'ssh %s\n' "\$*" >> "${MBF_MOCK_LOG}"
last="\${!#}"
env -i PATH="\$PATH" HOME="\${HOME:-/tmp}" bash -c "\$last"
EOF
    chmod +x "${MBF_MOCK_BIN}/ssh"
    local remote_out
    remote_out="$(bash "$mbf_bin" remote deploy@mock-host "$new_script" -- --dry-run 2>&1)"
    assert_contains "$remote_out" "Starting"
    assert_called_with "ssh" "deploy@mock-host bash -s -- --dry-run"

    # Test `mbf remote --self-remove` stages & deletes remote temp script after execution
    local remote_sr_out
    remote_sr_out="$(bash "$mbf_bin" remote --self-remove deploy@mock-host "$new_script" -- --dry-run 2>&1)"
    assert_contains "$remote_sr_out" "Starting"
    assert_called_with "ssh" "mbf.remote.XXXXXX"
}

function test_cli_plugin_manager_and_api_version_check() {
    local mbf_bin="${MBF_HOME}/bin/mbf"
    local work_dir user_plugins ext_src bad_api_ext
    mbf::exec::tmpdir work_dir
    user_plugins="${work_dir}/user_plugins"
    ext_src="${work_dir}/mycache.sh"
    bad_api_ext="${work_dir}/future_plugin.sh"

    bash "$mbf_bin" new --ext "$ext_src" >/dev/null
    assert_contains "$(cat "$ext_src")" "# @mbf-api: 1"

    export MBF_USER_DATA_DIR="${work_dir}/mbf_data"
    export MBF_USER_PLUGINS_DIR="$user_plugins"
    bash "$mbf_bin" plugin add "$ext_src" >/dev/null
    assert_file_exists "${user_plugins}/mycache.sh"
    assert_file_exists "${MBF_USER_DATA_DIR}/.installed_plugins"

    local plist_out
    plist_out="$(bash "$mbf_bin" plugin list)"
    assert_contains "$plist_out" "Installed Plugin Packages"
    assert_contains "$plist_out" "mycache"

    # Verify user-installed plugin is auto-resolved by `mbf::use`
    local load_out
    load_out="$(bash -c "MBF_USER_PLUGINS_DIR='${user_plugins}' source '${MBF_HOME}/framework.sh'; mbf::use mycache; mbf::mycache::run test-target")"
    assert_contains "$load_out" "Running mycache on test-target"

    bash "$mbf_bin" plugin remove mycache >/dev/null
    assert_eq "no" "$([ -f "${user_plugins}/mycache.sh" ] && echo yes || echo no)"
    unset MBF_USER_DATA_DIR

    # Verify `mbf doctor` rejects incompatible future `# @mbf-api: 99`
    cat <<'EOF' > "$bad_api_ext"
#!/usr/bin/env bash
# @mbf-module: futuremod
# @mbf-api: 99
function mbf::futuremod::run() {
    echo "future"
}
EOF
    local rc=0
    bash "$mbf_bin" doctor "$bad_api_ext" >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "mbf doctor must fail when @mbf-api exceeds current MBF_API_VERSION"
    unset MBF_USER_PLUGINS_DIR

    # Verify `mbf ai detect` CLI shortcut
    mock_cmd "claude" 0
    assert_eq "claude" "$(bash "$mbf_bin" ai detect)"

    # Verify `mbf completion <bash|zsh>` outputs valid completion scripts and rejects unknown shells
    local bash_comp zsh_comp
    bash_comp="$(bash "$mbf_bin" completion bash)"
    assert_contains "$bash_comp" "_mbf_completions()"
    assert_contains "$bash_comp" "complete -F _mbf_completions mbf"
    printf '%s\n' "$bash_comp" | bash -n

    zsh_comp="$(bash "$mbf_bin" completion zsh)"
    assert_contains "$zsh_comp" "bashcompinit"

    rc=0
    bash "$mbf_bin" completion fish >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "Unsupported completion shell should return 1"
}

run_test_suite "CLI End-to-End (bin/mbf)"
