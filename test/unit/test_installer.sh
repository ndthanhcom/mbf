#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use fs

function test_installer_rc_file_and_idempotency() {
    local mock_dir
    mbf::fs::tmpdir mock_dir
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

function test_mbf_cli_commands() {
    local mock_dir
    mbf::fs::tmpdir mock_dir

    local init_path
    init_path="$(bash "${MBF_HOME}/bin/mbf" --init)"
    assert_eq "${MBF_HOME}/framework.sh" "$init_path"

    local list_out
    list_out="$(bash "${MBF_HOME}/bin/mbf" list)"
    assert_contains "$list_out" "Core Libraries"
    assert_contains "$list_out" "Plugins"
    assert_contains "$list_out" "mbf::config::set"
    assert_contains "$list_out" "mbf::runtime::run_node"
    assert_not_contains "$list_out" "exporter"

    local new_script="${mock_dir}/my_script.sh"
    bash "${MBF_HOME}/bin/mbf" new "$new_script" >/dev/null
    assert_file_exists "$new_script"
}

run_test_suite "Installer & CLI (bin/mbf)"
