#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"

function test_module_loading_and_deduplication() {
    # Overwriting DIR in user script must NOT break _import or mbf_use
    DIR="/nonexistent/custom/user/dir"
    mbf_use config args auth
    _import config

    assert_eq "0" "$(mbf_is_loaded config && echo 0 || echo 1)" "config module should be marked loaded"
    assert_eq "0" "$(mbf_is_loaded args && echo 0 || echo 1)" "args module should be marked loaded"
    assert_eq "0" "$(function_exists modify_config_value && echo 0 || echo 1)" "modify_config_value should exist"
}

function test_basic_helpers() {
    assert_eq "yes" "$(in_list 74 73 74 81)" "in_list should find 74"
    assert_eq "no" "$(in_list 99 73 74 81)" "in_list should not find 99"

    local tmpf
    tmpf="$(mbf_mktemp_file)"
    printf '127.0.0.1 ndthanh.net\n' > "$tmpf"

    assert_eq "yes" "$(in_file "$tmpf" "127.0.0.1")" "in_file should find 127.0.0.1"
    assert_eq "no" "$(in_file "$tmpf" "abcxyz")" "in_file should not find abcxyz"
}

function test_dry_run_mode() {
    local tmpf
    tmpf="$(mbf_mktemp_file)"
    rm -f "$tmpf"

    MBF_DRYRUN="1"
    run_cmd "touch '$tmpf'" >/dev/null
    MBF_DRYRUN="0"

    assert_eq "no" "$([ -f "$tmpf" ] && echo yes || echo no)" "Dry run should not execute touch command"
}

function test_validate_program_and_require_env() {
    validate_program "bash" "warning" >/dev/null
    assert_eq "0" "$?" "bash should be a valid installed program"

    validate_program "nonexistent_mbf_bin_xyz" "warning" >/dev/null
    assert_eq "1" "$?" "nonexistent program should return 1"

    export MBF_TEST_ENV_VAR="hello"
    require_env MBF_TEST_ENV_VAR >/dev/null
    assert_eq "0" "$?" "require_env should succeed when variable is set"

    unset MBF_TEST_ENV_VAR
    require_env MBF_TEST_ENV_VAR >/dev/null 2>&1
    assert_eq "1" "$?" "require_env should fail when variable is unset"
}

function test_auth_token() {
    mbf_use auth
    local tok
    tok="$(generate_token)"
    validate_token "$tok"
    assert_eq "0" "$?" "Generated dynamic token should validate"

    validate_token "invalid_token" >/dev/null 2>&1
    assert_eq "1" "$?" "Invalid token should fail validation"
}

function test_logger_and_debugger_to_tmp_file() {
    local custom_log
    custom_log="$(mbf_mktemp_file)"
    rm -f "$custom_log"

    # 1. When MBF_LOG=0 and MBF_DEBUG=0, info logs should NOT write to file
    MBF_LOG="0"
    MBF_DEBUG="0"
    MBF_LOG_FILE="$custom_log"
    log_info "quiet message" >/dev/null
    assert_eq "no" "$([ -f "$custom_log" ] && echo yes || echo no)" "MBF_LOG=0 should not create log file"

    # 2. When MBF_LOG=1, logs and errors should be appended to MBF_LOG_FILE (/tmp)
    MBF_LOG="1"
    log_info "monitored info message" >/dev/null
    log_error "monitored error message" 2>/dev/null
    assert_file_exists "$custom_log"
    local log_content
    log_content="$(cat "$custom_log")"
    assert_contains "$log_content" "monitored info message"
    assert_contains "$log_content" "monitored error message"

    # 3. When MBF_DEBUG=1, log_debug outputs caller context and stack traces are included on error
    MBF_LOG="0"
    MBF_DEBUG="1"
    local dbg_out
    dbg_out="$(log_debug "step x=42" 2>&1)"
    assert_contains "$dbg_out" "[DEBUG]"
    assert_contains "$dbg_out" "test_logger_and_debugger_to_tmp_file"
    assert_contains "$dbg_out" "step x=42"

    local err_trace
    err_trace="$(log_error "simulated failure" 2>&1)"
    assert_contains "$err_trace" "Stack trace:"

    # 4. Failed run_cmd in subshell appends error to MBF_LOG_FILE when MBF_LOG=1
    MBF_LOG="1"
    MBF_DEBUG="0"
    (run_cmd "false" >/dev/null 2>&1) || true
    log_content="$(cat "$custom_log")"
    assert_contains "$log_content" "Error (exit 1): false"

    MBF_LOG="0"
    MBF_DEBUG="0"
}

function test_execution_helpers_and_mbf_update() {
    local scripts_dir
    scripts_dir="$(mbf_mktemp_dir)"

    printf '#!/usr/bin/env bash\necho "ran_sh_1"\n' > "${scripts_dir}/s1.sh"
    printf '#!/usr/bin/env bash\necho "ran_sh_2"\n' > "${scripts_dir}/s2.sh"
    chmod +x "${scripts_dir}/s1.sh" "${scripts_dir}/s2.sh"

    local dir_out
    dir_out="$(run_scripts_by_dir "$scripts_dir" bash sh)"
    assert_contains "$dir_out" "ran_sh_1"
    assert_contains "$dir_out" "ran_sh_2"

    # Test execute() with USAGE when no arguments are given vs with arguments
    USAGE="Usage: my_app <arg>"
    function _sample_entry() { echo "entry_arg=$1"; }
    local usage_out
    usage_out="$(execute _sample_entry)"
    assert_eq "1" "$?" "execute with no args and USAGE set should return 1"
    assert_contains "$usage_out" "Usage: my_app <arg>"

    local run_out
    run_out="$(execute _sample_entry "hello")"
    assert_contains "$run_out" "entry_arg=hello"
    USAGE=""

    # Test mbf_update dry-run and non-git directory handling
    MBF_DRYRUN="1"
    local upd_out
    upd_out="$(mbf_update "master")"
    assert_eq "0" "$?"
    assert_contains "$upd_out" "git -C"
    MBF_DRYRUN="0"

    local non_git_dir
    non_git_dir="$(mbf_mktemp_dir)"
    (MBF_HOME="$non_git_dir" mbf_update >/dev/null 2>&1)
    assert_eq "1" "$?" "mbf_update should fail if MBF_HOME is not a git repo"
}

run_test_suite "Core, Exec, Check & Auth"
