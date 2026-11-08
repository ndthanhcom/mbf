#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"

MOCK_DIR=""

function setup() {
    MOCK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mbf.install.XXXXXX")"
}

function teardown() {
    rm -rf "$MOCK_DIR"
}

function test_installer_rc_file_and_idempotency() {
    local mock_rc="${MOCK_DIR}/.bashrc"
    printf '# Existing user bashrc\nexport EDITOR=vim\n' > "$mock_rc"

    bash "${MBF_HOME}/install.sh" --in-place --rc-file "$mock_rc" >/dev/null
    bash "${MBF_HOME}/install.sh" --in-place --rc-file "$mock_rc" >/dev/null

    local rc_content
    rc_content="$(cat "$mock_rc")"
    assert_contains "$rc_content" "export MBF_HOME="
    assert_contains "$rc_content" "export PATH=\"\$MBF_HOME/bin:\$PATH\""

    local marker_count
    marker_count="$(grep -c "# >>> mbf initialize >>>" "$mock_rc")"
    assert_eq "1" "$marker_count" "Installer should be idempotent when run multiple times"
}

function test_mbf_cli_commands() {
    local init_path
    init_path="$(bash "${MBF_HOME}/bin/mbf" --init)"
    assert_eq "${MBF_HOME}/framework.sh" "$init_path"

    local list_out
    list_out="$(bash "${MBF_HOME}/bin/mbf" list)"
    assert_contains "$list_out" "config"
    assert_contains "$list_out" "exporter"

    local new_script="${MOCK_DIR}/my_script.sh"
    bash "${MBF_HOME}/bin/mbf" new "$new_script" >/dev/null
    assert_file_exists "$new_script"
}

run_test_suite "Installer & CLI (bin/mbf)"
