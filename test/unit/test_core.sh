#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"

function test_module_loading_and_custom_extension_resolution() {
    mbf::use exec system config

    assert_eq "0" "$(mbf::is_loaded exec && echo 0 || echo 1)"
    assert_eq "0" "$(mbf::is_loaded system && echo 0 || echo 1)"
    assert_eq "0" "$(declare -F mbf::config::set >/dev/null && echo 0 || echo 1)"

    # Create a contextual custom Magento extension in a project directory and load via MBF_EXT_PATH
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
    mbf::use magento 2>/dev/null
    MBF_DEBUG_EXT="0"

    assert_contains "$(cat "$ext_log_file")" "[EXT-DEBUG]"
    assert_contains "$(cat "$ext_log_file")" "Loading module 'magento'"
    assert_eq "FLUSHED_M2_CACHE" "$(mbf::magento::cache_flush)"
}

function test_exec_dryrun_locks_and_idempotent_deployment_steps() {
    mbf::use exec
    local work_dir
    mbf::exec::tmpdir work_dir
    local marker_file="${work_dir}/deployed.txt"

    MBF_DRYRUN="1"
    mbf::exec::run touch "$marker_file" >/dev/null
    assert_eq "no" "$([ -f "$marker_file" ] && echo yes || echo no)"

    MBF_DRYRUN="0"
    mbf::exec::run false >/dev/null 2>&1
    assert_eq "1" "$?" "mbf::exec::run should return non-zero without exiting caller shell"

    # Concurrency lock for deployment job
    MBF_LOCK_DIR="$work_dir"
    MBF_STATE_FILE="${work_dir}/deploy.steps"

    mbf::exec::lock_acquire "m2_deploy" 0
    assert_eq "0" "$?"
    mbf::exec::lock_acquire "m2_deploy" 0 >/dev/null 2>&1
    assert_eq "1" "$?" "Concurrent lock acquisition with live PID should fail"
    mbf::exec::lock_release "m2_deploy"

    # Idempotent deployment step checkpointing
    local count_file="${work_dir}/migration_runs"
    printf '0\n' > "$count_file"
    function _run_db_migration() {
        local c
        c="$(cat "$count_file")"
        printf '%d\n' $((c + 1)) > "$count_file"
    }

    mbf::exec::step_run "01_setup_upgrade" _run_db_migration >/dev/null
    mbf::exec::step_run "01_setup_upgrade" _run_db_migration >/dev/null
    assert_eq "1" "$(cat "$count_file")" "Idempotent step should only run once"
}

function test_logger_and_debugger_to_log_file() {
    mbf::use exec
    local custom_log
    mbf::exec::tmpfile custom_log
    rm -f "$custom_log"

    MBF_LOG="0"
    MBF_DEBUG="0"
    MBF_LOG_FILE="$custom_log"
    mbf::log::info "Starting Nginx reload" >/dev/null
    assert_eq "no" "$([ -f "$custom_log" ] && echo yes || echo no)"

    MBF_LOG="1"
    mbf::log::info "Deploying release 20261112" >/dev/null
    mbf::log::error "Upstream PHP-FPM socket timeout" 2>/dev/null
    assert_file_exists "$custom_log"
    local log_content
    log_content="$(cat "$custom_log")"
    assert_contains "$log_content" "Deploying release 20261112"
    assert_contains "$log_content" "Upstream PHP-FPM socket timeout"

    MBF_LOG="0"
    MBF_DEBUG="1"
    local dbg_out
    dbg_out="$(mbf::log::debug "Varnish purge status=200" 2>&1)"
    assert_contains "$dbg_out" "[DEBUG]"
    assert_contains "$dbg_out" "test_logger_and_debugger_to_log_file"
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
    assert_eq "0" "$?"
    assert_contains "$upd_out" "git -C"
    MBF_DRYRUN="0"
}

run_test_suite "Core Loader, Extensions, Log & Exec (framework.sh, log, exec)"
