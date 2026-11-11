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
    bash "${MBF_HOME}/install.sh" --in-place --rc-file "$mock_rc" >/dev/null

    local rc_content
    rc_content="$(cat "$mock_rc")"
    assert_contains "$rc_content" "export MBF_HOME="
    assert_contains "$rc_content" "export PATH=\"\$MBF_HOME/bin:\$PATH\""
    assert_eq "1" "$(grep -c "# >>> mbf initialize >>>" "$mock_rc")"
}

function test_mbf_cli_list_ranks_new_ext_and_doctor() {
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
    assert_eq "0" "$?"
}

run_test_suite "Installer & CLI (bin/mbf)"
