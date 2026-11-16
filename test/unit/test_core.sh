#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"

function test_module_loading_predicates_and_custom_extension_resolution() {
    mbf::use exec system config

    assert_eq "0" "$(mbf::is_loaded exec && echo 0 || echo 1)"
    assert_eq "0" "$(mbf::is_loaded system && echo 0 || echo 1)"
    assert_eq "0" "$(declare -F mbf::config::set >/dev/null && echo 0 || echo 1)"
    assert_eq "0" "$(mbf::in_list "redis" "nginx" "mysql" "redis" && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::in_list "varnish" "nginx" "mysql" && echo 0 || echo 1)"

    mock_cmd "sudo" 0
    MBF_SUDO="1" mbf::init
    mbf::exec::init_sudo
    MBF_SUDO="0"

    local proj_dir ext_log_file
    mbf::exec::tmpdir proj_dir
    mbf::exec::tmpfile ext_log_file
    mkdir -p "${proj_dir}/plugins"
    cat <<'EOF' > "${proj_dir}/plugins/magento.sh"
#!/usr/bin/env bash
# @mbf-module: magento
# @mbf-rank: ••
# mbf:requires log exec
function mbf::magento::cache_flush() {
    echo "FLUSHED_M2_CACHE"
}
EOF

    MBF_EXT_PATH="${proj_dir}/plugins"
    MBF_DEBUG_EXT="1"
    MBF_LOG_FILE="$ext_log_file"
    assert_eq "0" "$(mbf::log::is_debug_ext && echo 0 || echo 1)"
    mbf::use magento 2>/dev/null
    MBF_DEBUG_EXT="0"

    assert_contains "$(cat "$ext_log_file")" "[EXT-DEBUG]"
    assert_contains "$(cat "$ext_log_file")" "Loading module 'magento'"
    assert_eq "FLUSHED_M2_CACHE" "$(mbf::magento::cache_flush)"
}

function test_exec_dryrun_sudo_as_user_locks_and_steps() {
    mbf::use exec
    local work_dir
    mbf::exec::tmpdir work_dir
    local marker_file="${work_dir}/deployed.txt"

    MBF_DRYRUN="1"
    assert_eq "0" "$(mbf::is_dryrun && echo 0 || echo 1)"
    mbf::exec::run touch "$marker_file" >/dev/null
    assert_eq "no" "$([ -f "$marker_file" ] && echo yes || echo no)"

    MBF_DRYRUN="0"
    local rc=0
    mbf::exec::run false >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "mbf::exec::run should return non-zero without exiting caller shell"

    mock_cmd "sudo" 0 "SUDO_RAN_OK"
    mbf::exec::sudo systemctl reload nginx >/dev/null
    mbf::exec::as_user "www-data" php bin/magento cache:clean >/dev/null
    assert_called_with "sudo" "-H -u www-data -- php bin/magento cache:clean"

    # Concurrency lock + Stale lock recovery from crashed process
    MBF_LOCK_DIR="$work_dir"
    MBF_STATE_FILE="${work_dir}/deploy.steps"

    mkdir -p "${work_dir}/mbf.m2_deploy.lock"
    printf '999999\n' > "${work_dir}/mbf.m2_deploy.lock/pid"
    mbf::exec::lock_acquire "m2_deploy" 0 2>/dev/null
    assert_eq "0" "$?" "mbf::exec::lock_acquire should recover stale lock from dead PID"

    rc=0
    mbf::exec::lock_acquire "m2_deploy" 0 >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "Concurrent lock acquisition with live PID should fail"
    mbf::exec::lock_release "m2_deploy"

    # Idempotent deployment step checkpointing
    local count_file="${work_dir}/migration_runs"
    printf '0\n' > "$count_file"
    function _run_db_migration() {
        local c
        c="$(cat "$count_file")"
        printf '%d\n' $((c + 1)) > "$count_file"
    }

    assert_eq "1" "$(mbf::exec::step_done "01_setup_upgrade" && echo 0 || echo 1)"
    mbf::exec::step_run "01_setup_upgrade" _run_db_migration >/dev/null
    assert_eq "0" "$(mbf::exec::step_done "01_setup_upgrade" && echo 0 || echo 1)"
    mbf::exec::step_mark "02_manual_checkpoint"
    assert_eq "0" "$(mbf::exec::step_done "02_manual_checkpoint" && echo 0 || echo 1)"
    mbf::exec::step_run "01_setup_upgrade" _run_db_migration >/dev/null
    assert_eq "1" "$(cat "$count_file")" "Idempotent step should only run once"
}

function test_exec_retry_lifo_on_exit_traps_and_strict_mode() {
    mbf::use exec
    local work_dir attempt_file lifo_file
    mbf::exec::tmpdir work_dir
    attempt_file="${work_dir}/attempts"
    lifo_file="${work_dir}/lifo.log"
    printf '0\n' > "$attempt_file"

    function _flaky_healthcheck() {
        local n
        n="$(cat "$attempt_file")"
        n=$((n + 1))
        printf '%d\n' "$n" > "$attempt_file"
        [ "$n" -ge 3 ]
    }

    mbf::exec::retry 3 0 _flaky_healthcheck >/dev/null 2>&1
    assert_eq "3" "$(cat "$attempt_file")"

    # Verify LIFO execution order of multiple on_exit hooks in a subshell
    (
        mbf::exec::on_exit "printf 'first_registered\n' >> '$lifo_file'"
        mbf::exec::on_exit "printf 'second_registered\n' >> '$lifo_file'"
    )
    assert_eq $'second_registered\nfirst_registered' "$(cat "$lifo_file")"

    # Verify mbf::strict error trap logs failing command and line number
    local strict_out rc=0
    strict_out="$(bash -c "source '${MBF_HOME}/framework.sh'; mbf::strict; false" 2>&1)" || rc=$?
    assert_eq "1" "$rc"
    assert_contains "$strict_out" "exited with status 1"

    # Verify Bash version guard rejects Bash < 4
    local bash3_out b3_rc=0
    bash3_out="$(MBF_BASH_MAJOR_OVERRIDE=3 bash -c "source '${MBF_HOME}/framework.sh'" 2>&1)" || b3_rc=$?
    assert_eq "1" "$b3_rc"
    assert_contains "$bash3_out" "Bash >= 4.0 is required"
}

function test_logger_literal_backslashes_stderr_mode_and_die() {
    mbf::use exec
    local custom_log
    mbf::exec::tmpfile custom_log
    rm -f "$custom_log"

    MBF_LOG="0"
    MBF_DEBUG="0"
    MBF_LOG_FILE="$custom_log"
    mbf::log::info "Starting Nginx reload" >/dev/null
    assert_eq "1" "$(mbf::log::is_file_enabled && echo 0 || echo 1)"
    assert_eq "no" "$([ -f "$custom_log" ] && echo yes || echo no)"

    # Regression B5: literal backslashes (`C:\new\table`) must not be expanded as `\n` / `\t`
    local bs_out
    bs_out="$(NO_COLOR=1 mbf::log::info 'Windows path C:\new\table')"
    assert_contains "$bs_out" 'C:\new\table'

    # Regression B6: MBF_LOG_STDERR=1 sends info/ok to stderr so `$(...)` stays clean
    local stdout_captured
    stdout_captured="$(MBF_LOG_STDERR=1 mbf::log::info "Progress message" 2>/dev/null; MBF_LOG_STDERR=1 mbf::log::ok "Done" 2>/dev/null; printf 'PURE_DATA')"
    assert_eq "PURE_DATA" "$stdout_captured"

    MBF_LOG="1"
    mbf::log::info "Deploying release 20261116" >/dev/null
    mbf::log::warn "High memory usage" 2>/dev/null
    mbf::log::error "Upstream PHP-FPM socket timeout" 2>/dev/null
    assert_file_exists "$custom_log"
    local log_content
    log_content="$(cat "$custom_log")"
    assert_contains "$log_content" "Deploying release 20261116"
    assert_contains "$log_content" "Upstream PHP-FPM socket timeout"

    MBF_LOG="0"
    MBF_DEBUG="1"
    assert_eq "0" "$(mbf::log::is_debug && echo 0 || echo 1)"
    local dbg_out
    dbg_out="$(mbf::log::debug "Varnish purge status=200" 2>&1)"
    assert_contains "$dbg_out" "[DEBUG]"
    assert_contains "$dbg_out" "test_logger_literal_backslashes_stderr_mode_and_die"
    mbf::log::debug_ext "Custom extension trace" 2>/dev/null
    mbf::log::write_file "AUDIT" "Manual audit entry"
    assert_contains "$(mbf::log::stack_trace)" "Stack trace:"

    ( mbf::log::xtrace_on; mbf::log::xtrace_off ) >/dev/null 2>&1

    local die_out die_rc=0
    die_out="$( (mbf::die "Fatal configuration error") 2>&1 )" || die_rc=$?
    assert_eq "1" "$die_rc"
    assert_contains "$die_out" "Fatal configuration error"
}

function test_scripts_in_dir_and_mbf_update() {
    mbf::use exec
    local hooks_dir
    mbf::exec::tmpdir hooks_dir

    printf '#!/usr/bin/env bash\necho "hook_01_backup_db"\n' > "${hooks_dir}/01_backup.sh"
    printf '#!/usr/bin/env bash\necho "hook_02_warm_cache"\n' > "${hooks_dir}/02_warm.sh"
    chmod +x "${hooks_dir}/01_backup.sh" "${hooks_dir}/02_warm.sh"

    local dir_out
    dir_out="$(mbf::exec::scripts_in_dir "$hooks_dir" bash sh)"
    assert_contains "$dir_out" "hook_01_backup_db"
    assert_contains "$dir_out" "hook_02_warm_cache"

    MBF_DRYRUN="1"
    local upd_out
    upd_out="$(mbf::update "master")"
    assert_contains "$upd_out" "git -C"
    MBF_DRYRUN="0"

    # Verify built-in version management & monthly periodic update check
    assert_eq "1.0.0" "$(mbf::version)"
    assert_eq "2592000" "$MBF_UPDATE_CHECK_INTERVAL"
    assert_eq "${MBF_HOME}/.version_check" "$MBF_UPDATE_CHECK_FILE"
    assert_eq "0" "$(_mbf_version_gt "2.0.0" "1.9.9" && echo 0 || echo 1)"
    assert_eq "0" "$(_mbf_version_gt "1.1.0" "1.0.9" && echo 0 || echo 1)"
    assert_eq "0" "$(_mbf_version_gt "1.0.1" "1.0.0" && echo 0 || echo 1)"
    assert_eq "1" "$(_mbf_version_gt "1.0.0" "1.0.0" && echo 0 || echo 1)"

    local cache_file="${hooks_dir}/.version_check"
    export MBF_UPDATE_CHECK_FILE="$cache_file"

    # 1. Stale/missing cache: fetches remote version via curl and prompts user to run `mbf update`
    mock_cmd "curl" 0 'MBF_VERSION="1.2.0"'
    local chk_out
    chk_out="$(mbf::check_update --force 2>&1)"
    assert_contains "$chk_out" "A new version of mbf is available: v1.2.0 (current: v1.0.0). Run 'mbf update' to upgrade."
    assert_file_exists "$cache_file"
    assert_contains "$(cat "$cache_file")" " 1.2.0"

    # 2. Fresh cache within 30-day interval: reads cached version without calling curl
    : > "$MBF_MOCK_LOG"
    printf '%s 1.0.0\n' "$(date +%s)" > "$cache_file"
    chk_out="$(mbf::check_update 2>&1)"
    assert_eq "" "$(cat "$MBF_MOCK_LOG")" "Fresh monthly cache must not invoke curl"
    unset MBF_UPDATE_CHECK_FILE
}

run_test_suite "Core Loader, Extensions, Strict Mode, Log & Exec"
