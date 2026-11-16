#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use exec

function test_installer_rc_file_and_idempotency() {
    local mock_dir
    mbf::exec::tmpdir mock_dir
    local mock_rc="${mock_dir}/.bashrc"
    printf '# Existing user bashrc\nexport EDITOR=vim\n' > "$mock_rc"

    bash "${MBF_HOME}/install.sh" --in-place --rc-file "$mock_rc" >/dev/null
    local first_rc
    first_rc="$(cat "$mock_rc")"
    bash "${MBF_HOME}/install.sh" --in-place --rc-file "$mock_rc" >/dev/null

    assert_eq "$first_rc" "$(cat "$mock_rc")" "Re-running install.sh must produce byte-identical rc file"
    assert_contains "$first_rc" "export MBF_HOME="
    assert_contains "$first_rc" "export PATH=\"\$MBF_HOME/bin:\$PATH\""
    assert_eq "1" "$(grep -c "# >>> mbf initialize >>>" "$mock_rc")"
}

function test_mbf_cli_list_ranks_new_ext_doctor_and_unknown_cmd() {
    local mock_dir
    mbf::exec::tmpdir mock_dir

    local init_path
    init_path="$(bash "${MBF_HOME}/bin/mbf" --init)"
    assert_eq "${MBF_HOME}/framework.sh" "$init_path"

    local list_out
    list_out="$(bash "${MBF_HOME}/bin/mbf" list)"
    assert_contains "$list_out" "Core Libraries"
    assert_contains "$list_out" "Plugins"
    assert_contains "$list_out" "[••••]"
    assert_contains "$list_out" "mbf::ai::ask"
    assert_contains "$list_out" "mbf::backup::archive_dir"
    assert_contains "$list_out" "mbf::config::set"

    # Generate new script and new custom extension via `mbf new`
    local new_script="${mock_dir}/deploy.sh"
    local new_ext="${mock_dir}/jenkins.sh"
    bash "${MBF_HOME}/bin/mbf" new "$new_script" >/dev/null
    bash "${MBF_HOME}/bin/mbf" new --ext "$new_ext" >/dev/null

    assert_file_exists "$new_script"
    assert_file_exists "$new_ext"
    assert_contains "$(cat "$new_ext")" "# @mbf-module: jenkins"
    assert_contains "$(cat "$new_ext")" "function mbf::jenkins::run()"

    # Validate generated extension with `mbf doctor`
    bash "${MBF_HOME}/bin/mbf" doctor "$new_ext" >/dev/null

    # Unknown CLI command must exit with status 1
    local unk_rc=0
    bash "${MBF_HOME}/bin/mbf" unknown_subcommand >/dev/null 2>&1 || unk_rc=$?
    assert_eq "1" "$unk_rc"
}

function test_public_api_contract_matches_documentation() {
    # Every public `mbf::*` function in framework.sh, lib/*.sh, and plugins/*.sh
    # must be documented in docs/LIBRARIES.md or docs/PLUGINS.md.
    local f fn missing=""
    for f in "${MBF_HOME}/framework.sh" "${MBF_HOME}"/lib/*.sh "${MBF_HOME}"/plugins/*.sh; do
        while IFS= read -r fn; do
            [ -z "$fn" ] && continue
            if ! grep -Fq "$fn" "${MBF_HOME}/docs/LIBRARIES.md" "${MBF_HOME}/docs/PLUGINS.md"; then
                missing="${missing} ${fn}"
            fi
        done < <(grep -oE '^function[[:space:]]+mbf::[a-zA-Z0-9_:]+' "$f" | awk '{print $2}')
    done
    assert_eq "" "${missing# }" "Undocumented public mbf::* functions found:${missing}"
}

run_test_suite "Installer, CLI & Public API Contract (bin/mbf, docs/)"
