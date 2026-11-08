#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"

function test_module_loading_and_requires_resolution() {
    # Loading `runtime` plugin should automatically resolve `# mbf:requires log exec check`
    mbf::use runtime config fs
    mbf::use config

    assert_eq "0" "$(mbf::is_loaded runtime && echo 0 || echo 1)"
    assert_eq "0" "$(mbf::is_loaded exec && echo 0 || echo 1)"
    assert_eq "0" "$(mbf::is_loaded check && echo 0 || echo 1)"
    assert_eq "0" "$(mbf::function_exists mbf::config::set && echo 0 || echo 1)"
}

function test_return_code_predicates_and_fs_tmp() {
    mbf::use fs
    assert_eq "0" "$(mbf::in_list 74 73 74 81 && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::in_list 99 73 74 81 && echo 0 || echo 1)"

    local tmpf
    mbf::fs::tmpfile tmpf
    assert_file_exists "$tmpf"
    printf '127.0.0.1 ndthanh.net\n' > "$tmpf"

    assert_eq "0" "$(mbf::in_file "$tmpf" "127.0.0.1" && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::in_file "$tmpf" "abcxyz" && echo 0 || echo 1)"
}

function test_exec_run_returns_status_without_exit() {
    mbf::use exec fs
    local tmpf
    mbf::fs::tmpfile tmpf
    rm -f "$tmpf"

    MBF_DRYRUN="1"
    mbf::exec::run touch "$tmpf" >/dev/null
    assert_eq "no" "$([ -f "$tmpf" ] && echo yes || echo no)"

    MBF_DRYRUN="0"
    mbf::exec::run false >/dev/null 2>&1
    local rc=$?
    assert_eq "1" "$rc" "mbf::exec::run should return non-zero without killing the caller shell"
}

function test_check_cmd_and_env() {
    mbf::use check
    mbf::check::cmd "bash" >/dev/null
    assert_eq "0" "$?"

    mbf::check::cmd "nonexistent_mbf_bin_xyz" >/dev/null 2>&1
    assert_eq "1" "$?"

    export MBF_TEST_ENV_VAR="hello"
    mbf::check::env MBF_TEST_ENV_VAR >/dev/null
    assert_eq "0" "$?"

    unset MBF_TEST_ENV_VAR
    mbf::check::env MBF_TEST_ENV_VAR >/dev/null 2>&1
    assert_eq "1" "$?"
}

function test_logger_and_debugger_to_tmp_file() {
    mbf::use exec fs
    local custom_log
    mbf::fs::tmpfile custom_log
    rm -f "$custom_log"

    MBF_LOG="0"
    MBF_DEBUG="0"
    MBF_LOG_FILE="$custom_log"
    mbf::log::info "quiet message" >/dev/null
    assert_eq "no" "$([ -f "$custom_log" ] && echo yes || echo no)"

    MBF_LOG="1"
    mbf::log::info "monitored info message" >/dev/null
    mbf::log::error "monitored error message" 2>/dev/null
    assert_file_exists "$custom_log"
    local log_content
    log_content="$(cat "$custom_log")"
    assert_contains "$log_content" "monitored info message"
    assert_contains "$log_content" "monitored error message"

    MBF_LOG="0"
    MBF_DEBUG="1"
    local dbg_out
    dbg_out="$(mbf::log::debug "step x=42" 2>&1)"
    assert_contains "$dbg_out" "[DEBUG]"
    assert_contains "$dbg_out" "test_logger_and_debugger_to_tmp_file"

    local err_trace
    err_trace="$(mbf::log::error "simulated failure" 2>&1)"
    assert_contains "$err_trace" "Stack trace:"
}

function test_scripts_in_dir_and_mbf_update() {
    mbf::use exec fs
    local scripts_dir
    mbf::fs::tmpdir scripts_dir

    printf '#!/usr/bin/env bash\necho "ran_sh_1"\n' > "${scripts_dir}/s1.sh"
    printf '#!/usr/bin/env bash\necho "ran_sh_2"\n' > "${scripts_dir}/s2.sh"
    chmod +x "${scripts_dir}/s1.sh" "${scripts_dir}/s2.sh"

    local dir_out
    dir_out="$(mbf::exec::scripts_in_dir "$scripts_dir" bash sh)"
    assert_contains "$dir_out" "ran_sh_1"
    assert_contains "$dir_out" "ran_sh_2"

    MBF_DRYRUN="1"
    local upd_out
    upd_out="$(mbf::update "master")"
    assert_eq "0" "$?"
    assert_contains "$upd_out" "git -C"
    MBF_DRYRUN="0"

    local non_git_dir
    mbf::fs::tmpdir non_git_dir
    MBF_HOME="$non_git_dir" mbf::update >/dev/null 2>&1
    assert_eq "1" "$?"
}

run_test_suite "Core Loader, Log, Exec, Check & FS"
