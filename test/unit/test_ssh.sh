#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use ssh exec

# Helper: create a local-execution `ssh` stub that logs args and executes the
# final remote command argument in a clean `env -i` shell (simulating an agentless server).
function _install_local_ssh_stub() {
    cat <<EOF > "${MBF_MOCK_BIN}/ssh"
#!/usr/bin/env bash
printf 'ssh %s\n' "\$*" >> "${MBF_MOCK_LOG}"
# Extract the last argument as the remote command when not running -MNf / -O exit
prev=""
is_ctl=0
for a in "\$@"; do
    case "\$a" in
        -MNf|-N|-O) is_ctl=1 ;;
    esac
done
if [ "\$is_ctl" -eq 1 ]; then
    exit 0
fi
last="\${!#}"
env -i PATH="\$PATH" HOME="\${HOME:-/tmp}" bash -c "\$last"
EOF
    chmod +x "${MBF_MOCK_BIN}/ssh"
}

function test_ssh_open_close_run_and_dryrun() {
    local work_dir
    mbf::exec::tmpdir work_dir
    export MBF_SSH_MUX_DIR="${work_dir}/mux"
    export MBF_SSH_PORT="2222"
    export MBF_SSH_KEY="${work_dir}/id_ed25519"
    touch "$MBF_SSH_KEY"

    mock_cmd "ssh" 0 "REMOTE_OK"
    mbf::ssh::open "deploy@web-01.example.com"
    assert_called_with "ssh" "-p 2222 -i ${MBF_SSH_KEY}"
    assert_called_with "ssh" "ControlMaster=yes"

    local out
    out="$(mbf::ssh::run "deploy@web-01.example.com" echo "hello world")"
    assert_eq "REMOTE_OK" "$out"
    assert_called_with "ssh" "deploy@web-01.example.com echo hello\\ world"

    mbf::ssh::close "deploy@web-01.example.com"

    # Dry-run must not invoke ssh
    : > "$MBF_MOCK_LOG"
    MBF_DRYRUN="1"
    mbf::ssh::run "deploy@web-01.example.com" rm -rf /tmp/test >/dev/null
    MBF_DRYRUN="0"
    assert_not_called_with "ssh"

    unset MBF_SSH_PORT MBF_SSH_KEY MBF_SSH_MUX_DIR
}

function test_ssh_run_bash_and_agentless_exec_script() {
    local work_dir remote_script
    mbf::exec::tmpdir work_dir
    remote_script="${work_dir}/remote_task.sh"

    _install_local_ssh_stub

    # 1. Stream multi-line bash with arguments via run_bash
    local bash_out
    bash_out="$(mbf::ssh::run_bash "deploy@web-01" 'printf "ARG1=%s|ARG2=%s\n" "$1" "$2"' "hello world" "prod")"
    assert_eq "ARG1=hello world|ARG2=prod" "$bash_out"

    # 2. Agentless exec_script: local MBF script exported & executed in env -i (no MBF_HOME!)
    cat <<'EOF' > "$remote_script"
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::strict
mbf::use str
printf 'SLUG=%s\n' "$(mbf::str::slugify "$1")"
EOF

    local exec_out
    exec_out="$(mbf::ssh::exec_script "deploy@web-01" "$remote_script" "Magento 2 Prod!")"
    assert_eq "SLUG=magento-2-prod" "$exec_out"

    # 3. --self-remove mode: stages to 0700 temp file (real $0), executes, and deletes itself on exit
    local self_rm_script="${work_dir}/self_rm_task.sh"
    cat <<'EOF' > "$self_rm_script"
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::strict
mbf::use str
printf 'SCRIPT_PATH=%s\n' "${BASH_SOURCE[0]:-$0}"
printf 'SLUG=%s\n' "$(mbf::str::slugify "$1")"
[ "${2:-ok}" == "fail" ] && exit 1
EOF

    local sr_out sr_path
    sr_out="$(mbf::ssh::exec_script --self-remove "deploy@web-01" "$self_rm_script" "Self Clean!")"
    assert_contains "$sr_out" "SLUG=self-clean"
    sr_path="$(printf '%s\n' "$sr_out" | awk -F= '/^SCRIPT_PATH=/{print $2}')"
    assert_ne "" "$sr_path" "Self-remove staged script should run from a real file path"
    assert_eq "no" "$([ -e "$sr_path" ] && echo yes || echo no)" "Staged remote script must remove itself after execution"

    # Self-remove must ALSO delete the staged script when the script exits non-zero
    local fail_out fail_path fail_rc=0
    fail_out="$(mbf::ssh::exec_script --self-remove "deploy@web-01" "$self_rm_script" "Fail Case" "fail" 2>/dev/null)" || fail_rc=$?
    assert_eq "1" "$fail_rc"
    fail_path="$(printf '%s\n' "$fail_out" | awk -F= '/^SCRIPT_PATH=/{print $2}')"
    assert_ne "" "$fail_path"
    assert_eq "no" "$([ -e "$fail_path" ] && echo yes || echo no)" "Staged remote script must remove itself even on failure"
}

function test_ssh_upload_sync_and_run_many() {
    local work_dir src_dir src_file
    mbf::exec::tmpdir work_dir
    src_dir="${work_dir}/build"
    src_file="${work_dir}/app.env"
    mkdir -p "$src_dir"
    printf 'APP_ENV=prod\n' > "$src_file"

    mock_cmd "scp" 0
    mock_cmd "rsync" 0
    export MBF_SSH_PORT="2200"
    export MBF_SSH_OPTS="-o StrictHostKeyChecking=no"

    mbf::ssh::upload "deploy@web-01" "$src_file" "/var/www/shared/.env"
    assert_called_with "scp" "-P 2200"
    assert_called_with "scp" "-o StrictHostKeyChecking=no"
    assert_called_with "scp" "deploy@web-01:/var/www/shared/.env"

    mbf::ssh::download "deploy@web-01" "/tmp/audit.json" "${work_dir}/reports/audit.json"
    assert_called_with "scp" "-o StrictHostKeyChecking=no"
    assert_called_with "scp" "deploy@web-01:/tmp/audit.json ${work_dir}/reports/audit.json"

    mbf::ssh::sync "deploy@web-01" "$src_dir" "/var/www/releases/r1" --exclude=".git"
    assert_called_with "rsync" "-az --delete"
    assert_called_with "rsync" "--exclude=.git"

    mock_cmd "ssh" 0 "UP_OK"
    local seq_out par_out
    seq_out="$(mbf::ssh::run_many "web-01,web-02" uptime)"
    assert_contains "$seq_out" "[web-01] UP_OK"
    assert_contains "$seq_out" "[web-02] UP_OK"

    par_out="$(MBF_SSH_PARALLEL=1 MBF_SSH_MAX_JOBS=2 mbf::ssh::run_many "web-01 web-02 web-03" uptime)"
    assert_contains "$par_out" "[web-01] UP_OK"
    assert_contains "$par_out" "[web-02] UP_OK"
    assert_contains "$par_out" "[web-03] UP_OK"

    unset MBF_SSH_PORT MBF_SSH_OPTS
}

function test_ssh_user_password_check_and_prompt() {
    mock_cmd "ssh" 0 "PING_OK"

    # 1. MBF_SSH_USER + MBF_SSH_HOST resolution (explicit user@ overrides MBF_SSH_USER)
    export MBF_SSH_USER="ops"
    export MBF_SSH_HOST="web-01.internal"
    assert_eq "ops@web-01.internal" "$(_mbf_ssh_target "")"
    assert_eq "root@web-02.internal" "$(_mbf_ssh_target "root@web-02.internal")"

    # 2. Pre-flight mbf::ssh::check (success, failure, dry-run)
    mbf::ssh::check >/dev/null 2>&1
    assert_called_with "ssh" "ops@web-01.internal true"

    mock_cmd "ssh" 255 "Connection refused"
    local chk_rc=0
    mbf::ssh::check "web-01.internal" >/dev/null 2>&1 || chk_rc=$?
    assert_eq "255" "$chk_rc"

    MBF_DRYRUN="1"
    mbf::ssh::check "web-01.internal" >/dev/null 2>&1
    MBF_DRYRUN="0"

    # 3. Safe MBF_SSH_PASSWORD via sshpass -e (never on argv) + auto log redaction
    cat <<EOF > "${MBF_MOCK_BIN}/sshpass"
#!/usr/bin/env bash
printf 'sshpass %s\n' "\$*" >> "${MBF_MOCK_LOG}"
[ "\$1" == "-e" ] && shift
"\$@"
EOF
    chmod +x "${MBF_MOCK_BIN}/sshpass"
    mock_cmd "ssh" 0 "PASS_AUTH_OK"
    : > "$MBF_MOCK_LOG"

    export MBF_SSH_PASSWORD="MySuperSecretSshPass99!"
    local pw_out
    pw_out="$(mbf::ssh::run "web-01.internal" echo ok)"
    assert_eq "PASS_AUTH_OK" "$pw_out"
    assert_called_with "sshpass" "-e ssh"
    assert_not_called_with "sshpass" "MySuperSecretSshPass99!"
    assert_not_called_with "ssh" "BatchMode=yes"

    # Verify MBF_SSH_PASSWORD is auto-registered with mbf::log::redact in current shell
    mbf::ssh::check "web-01.internal" >/dev/null 2>&1
    local log_line
    log_line="$(NO_COLOR=1 mbf::log::info "pw=${MBF_SSH_PASSWORD}" 2>&1)"
    assert_not_contains "$log_line" "MySuperSecretSshPass99!"
    assert_contains "$log_line" "pw=***"

    # 4. mbf::ssh::prompt fails fast in CI when MBF_SSH_HOST is unset, succeeds + verifies when set
    unset MBF_SSH_PASSWORD MBF_SSH_HOST
    local pr_rc=0
    CI=1 mbf::ssh::prompt >/dev/null 2>&1 || pr_rc=$?
    assert_eq "1" "$pr_rc" "mbf::ssh::prompt must fail fast in CI when MBF_SSH_HOST is empty"

    export MBF_SSH_HOST="web-01.internal"
    CI=1 mbf::ssh::prompt --verify >/dev/null 2>&1
    assert_called_with "ssh" "ops@web-01.internal true"

    unset MBF_SSH_USER MBF_SSH_HOST
}

run_test_suite "SSH Remote Execution & Agentless Script Runner (lib/ssh.sh)"
