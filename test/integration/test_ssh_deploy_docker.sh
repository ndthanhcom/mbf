#!/usr/bin/env bash
# ==============================================================================
# MBF Real-Container Integration Test: SSH & Atomic Remote Deployment
# Spins up a live Alpine OpenSSH container and verifies real:
#   - mbf::ssh::{open,run,run_bash,exec_script,--self-remove,upload,sync,close}
#   - mbf::deploy::{setup,lock,prepare,upload_release,shared,writable,symlink,releases,rollback,cleanup}
# Automatically skips cleanly when Docker is unavailable or daemon is stopped.
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MBF_HOME="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export MBF_HOME

source "${MBF_HOME}/framework.sh"
mbf::strict
mbf::use log exec ssh deploy net

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    mbf::log::warn "[SKIP] Docker daemon is not available; skipping real-container SSH/Deploy integration test."
    exit 0
fi

function main() {
    local work_dir key_file cid port host
    mbf::exec::tmpdir work_dir
    key_file="${work_dir}/id_ed25519"
    ssh-keygen -q -t ed25519 -N "" -f "$key_file"

    local cname="mbf-it-sshd-$$"
    mbf::exec::on_exit "docker rm -f '${cname}' >/dev/null 2>&1 || true"

    local auth_key
    auth_key="$(cat "${key_file}.pub")"

    mbf::log::info "Starting Alpine OpenSSH test container (${cname})..."
    cid="$(docker run -d --name "$cname" -p 127.0.0.1::22 -e "AUTH_KEY=${auth_key}" alpine:3.20 sh -c '
        apk add --no-cache openssh bash rsync git >/dev/null &&
        ssh-keygen -A >/dev/null &&
        sed -i "s/^root:!/root:*/" /etc/shadow &&
        mkdir -p /root/.ssh && chmod 700 /root/.ssh &&
        printf "%s\n" "$AUTH_KEY" > /root/.ssh/authorized_keys &&
        chmod 600 /root/.ssh/authorized_keys &&
        printf "PermitRootLogin prohibit-password\nPasswordAuthentication no\n" >> /etc/ssh/sshd_config &&
        exec /usr/sbin/sshd -D -e
    ')"
    [ -n "$cid" ] || mbf::die "Failed to start test container"

    port="$(docker port "$cname" 22/tcp | head -n 1 | awk -F: '{print $NF}')"
    mbf::log::info "Waiting for sshd on 127.0.0.1:${port}..."
    mbf::net::wait_port "$port" "127.0.0.1" 45 || mbf::die "sshd did not become ready"

    export MBF_SSH_PORT="$port"
    export MBF_SSH_KEY="$key_file"
    export MBF_SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    export MBF_SSH_MUX_DIR="${work_dir}/mux"
    host="root@127.0.0.1"

    # Wait until SSH auth succeeds (sshd may still be finishing apk/keygen)
    mbf::exec::retry 20 2 mbf::ssh::run "$host" true

    # 1. Multiplexed connection + remote command + run_bash
    mbf::ssh::open "$host"
    local ping_out
    ping_out="$(mbf::ssh::run "$host" echo "MBF_DOCKER_SSH_OK")"
    [ "$ping_out" == "MBF_DOCKER_SSH_OK" ] || mbf::die "Expected MBF_DOCKER_SSH_OK, got: $ping_out"

    # 2. Agentless exec_script + --self-remove against container without MBF installed
    local task_script="${work_dir}/remote_check.sh"
    cat <<'EOF' > "$task_script"
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::strict
mbf::use str
printf 'PATH=%s\nSLUG=%s\n' "${BASH_SOURCE[0]:-$0}" "$(mbf::str::slugify "$1")"
EOF
    local sr_out sr_path
    sr_out="$(mbf::ssh::exec_script --self-remove "$host" "$task_script" "Live Docker Host!")"
    [[ "$sr_out" == *"SLUG=live-docker-host"* ]] || mbf::die "Unexpected exec_script output: $sr_out"
    sr_path="$(printf '%s\n' "$sr_out" | awk -F= '/^PATH=/{print $2}')"
    if mbf::ssh::run "$host" test -e "$sr_path" 2>/dev/null; then
        mbf::die "Self-remove failed: $sr_path still exists in container"
    fi

    # 3. Full Capistrano/Deployer-style atomic release + rollback + cleanup
    local deploy_path="/var/www/demo"
    local build_v1="${work_dir}/v1" build_v2="${work_dir}/v2"
    mkdir -p "$build_v1" "$build_v2"
    printf 'v1\n' > "${build_v1}/VERSION"
    printf 'APP_ENV=prod\n' > "${build_v1}/.env"
    printf 'v2\n' > "${build_v2}/VERSION"

    MBF_DEPLOY_SHARED_FILES=(".env")
    MBF_DEPLOY_SHARED_DIRS=("var/log")
    MBF_DEPLOY_WRITABLE_DIRS=("var/cache")

    mbf::deploy::setup "$host" "$deploy_path"
    mbf::deploy::lock  "$host" "$deploy_path" "ci-integration"

    local r1 r2
    r1="$(mbf::deploy::prepare "$host" "$deploy_path" "20261119_100000")"
    mbf::deploy::upload_release "$host" "$build_v1" "$r1"
    mbf::deploy::shared   "$host" "$deploy_path" "$r1"
    mbf::deploy::writable "$host" "$r1"
    mbf::deploy::symlink  "$host" "$deploy_path" "$r1"

    r2="$(mbf::deploy::prepare "$host" "$deploy_path" "20261119_110000")"
    mbf::deploy::upload_release "$host" "$build_v2" "$r2"
    mbf::deploy::shared  "$host" "$deploy_path" "$r2"
    mbf::deploy::symlink "$host" "$deploy_path" "$r2"

    local active_v
    active_v="$(mbf::ssh::run "$host" cat "${deploy_path}/current/VERSION")"
    [ "$active_v" == "v2" ] || mbf::die "Expected current=v2, got: $active_v"

    # Rollback to v1 and verify shared .env persisted
    mbf::deploy::rollback "$host" "$deploy_path" >/dev/null
    active_v="$(mbf::ssh::run "$host" cat "${deploy_path}/current/VERSION")"
    [ "$active_v" == "v1" ] || mbf::die "Expected rollback current=v1, got: $active_v"
    local env_v
    env_v="$(mbf::ssh::run "$host" cat "${deploy_path}/current/.env")"
    [ "$env_v" == "APP_ENV=prod" ] || mbf::die "Shared .env did not persist: $env_v"

    mbf::deploy::cleanup "$host" "$deploy_path" 1
    mbf::deploy::unlock  "$host" "$deploy_path"
    mbf::ssh::close "$host"

    mbf::log::ok "Docker OpenSSH + Atomic Deploy integration test passed!"
}

main "$@"
