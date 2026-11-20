#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use system net exec

function test_cross_environment_detection_and_pkg_manager() {
    local current_env arch ver
    current_env="$(mbf::system::env_type)"
    arch="$(mbf::system::arch)"
    ver="$(mbf::system::version)"
    assert_ne "" "$current_env"
    assert_ne "" "$arch"
    assert_ne "" "$ver"

    # Simulate Android Termux environment
    local termux_env termux_prefix
    termux_env="$(TERMUX_VERSION="0.118.0" mbf::system::env_type)"
    assert_eq "termux" "$termux_env"

    termux_prefix="$(TERMUX_VERSION="0.118.0" PREFIX="/data/data/com.termux/files/usr" mbf::system::prefix)"
    assert_eq "/data/data/com.termux/files/usr" "$termux_prefix"

    assert_eq "gitbash" "$(MBF_ENV_TYPE_OVERRIDE="gitbash" mbf::system::distro)"
    assert_eq "macos" "$(MBF_ENV_TYPE_OVERRIDE="macos" mbf::system::distro)"

    # Verify real argv of package managers using stub harness
    mock_cmd "apt-get" 0
    mock_cmd "dpkg-query" 0 "install ok installed"
    export MBF_PKG_MANAGER_OVERRIDE="apt-get"
    export MBF_ENV_TYPE_OVERRIDE="gitbash"
    assert_eq "apt-get" "$(mbf::system::pkg_manager)"
    mbf::system::pkg_update >/dev/null
    mbf::system::pkg_install nginx redis-server >/dev/null
    assert_called_with "apt-get" "update -qq"
    assert_called_with "apt-get" "install -y -qq nginx redis-server"
    assert_eq "0" "$(mbf::system::pkg_is_installed nginx && echo 0 || echo 1)"
    unset MBF_PKG_MANAGER_OVERRIDE MBF_ENV_TYPE_OVERRIDE
}

function test_service_controller_pre_flight_checks_and_validators() {
    mock_cmd "systemctl" 1
    export MBF_ENV_TYPE_OVERRIDE="gitbash"
    assert_eq "1" "$(mbf::system::service_is_active "varnish" && echo 0 || echo 1)"
    mock_cmd "systemctl" 0
    mbf::system::service "start" "nginx" >/dev/null
    assert_called_with "systemctl" "start nginx"
    mbf::system::service "reload" "nginx" >/dev/null
    assert_called_with "systemctl" "reload nginx"
    mbf::system::service "restart" "nginx" >/dev/null
    assert_called_with "systemctl" "restart nginx"
    mbf::system::service "stop" "nginx" >/dev/null
    assert_called_with "systemctl" "stop nginx"
    mbf::system::service "disable" "apache2" >/dev/null
    assert_called_with "systemctl" "disable apache2"
    mbf::system::service_ensure "varnish" >/dev/null
    assert_called_with "systemctl" "enable varnish"

    local svc_rc=0
    mbf::system::service "bogus_action" "nginx" >/dev/null 2>&1 || svc_rc=$?
    assert_eq "1" "$svc_rc" "Invalid service action should fail"
    unset MBF_ENV_TYPE_OVERRIDE

    assert_eq "0" "$(mbf::system::check_cmd "bash" && echo 0 || echo 1)"
    mock_cmd "fake_tool" 0 "GNU fake_tool, version 5.2.26(1)-release (x86_64-pc-linux-gnu)"
    assert_eq "0" "$(mbf::system::check_cmd "fake_tool" "5.2.26" && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::system::check_cmd "fake_tool" "5.3.0" 2>/dev/null && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::system::check_cmd "mbf_nonexistent_cmd_xyz" 2>/dev/null && echo 0 || echo 1)"
    assert_eq "0" "$(mbf::system::check_cmds "bash" "awk" && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::system::check_cmds "bash" "mbf_nonexistent_cmd_xyz" 2>/dev/null && echo 0 || echo 1)"
    export SAMPLE_REQUIRED_VAR="ready"
    assert_eq "0" "$(mbf::system::check_env "SAMPLE_REQUIRED_VAR" && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::system::check_env "MBF_UNSET_REQUIRED_VAR_XYZ" 2>/dev/null && echo 0 || echo 1)"

    assert_eq "0" "$(mbf::system::is_alnum "m2_prod_db" && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::system::is_alnum "m2-prod!" && echo 0 || echo 1)"

    assert_eq "0" "$(mbf::system::is_domain "store.example.com" && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::system::is_domain "invalid_domain" && echo 0 || echo 1)"

    assert_eq "0" "$(mbf::system::is_ip "10.240.0.15" && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::system::is_ip "999.240.0.15" && echo 0 || echo 1)"

    assert_eq "0" "$(mbf::system::is_email "devops@example.com" && echo 0 || echo 1)"
    assert_eq "1" "$(mbf::system::is_email "devops@invalid" && echo 0 || echo 1)"
}

function test_deploy_user_ssh_keys_and_sudoers() {
    local work_dir auth_keys sudoers_dir
    mbf::exec::tmpdir work_dir
    auth_keys="${work_dir}/.ssh/authorized_keys"
    sudoers_dir="${work_dir}/sudoers.d"

    mock_cmd "id" 1
    mock_cmd "useradd" 0
    export MBF_ENV_TYPE_OVERRIDE="gitbash"
    assert_eq "1" "$(mbf::system::user_exists "deployer" && echo 0 || echo 1)"
    mbf::system::as_root echo "root_check" >/dev/null
    mbf::system::user_ensure "deployer" "/home/deployer" "/bin/bash" >/dev/null
    assert_called_with "useradd" "-m -d /home/deployer -s /bin/bash deployer"
    unset MBF_ENV_TYPE_OVERRIDE

    mbf::system::ssh_key_add "deployer" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMagentoDeployKey deployer@ci" "$auth_keys"
    mbf::system::ssh_key_add "deployer" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMagentoDeployKey deployer@ci" "$auth_keys"
    assert_eq "1" "$(grep -c "AAAAC3NzaC1lZDI1NTE5AAAAIMagentoDeployKey" "$auth_keys")"

    mbf::system::ssh_key_remove "deployer" "AAAAC3NzaC1lZDI1NTE5AAAAIMagentoDeployKey" "$auth_keys"
    assert_eq "0" "$(grep -c "AAAAC3NzaC1lZDI1NTE5AAAAIMagentoDeployKey" "$auth_keys" || true)"

    mbf::system::sudo_nopasswd "deployer" "/usr/bin/systemctl reload php8.2-fpm, /usr/bin/systemctl reload nginx" "$sudoers_dir"
    assert_contains "$(cat "${sudoers_dir}/deployer")" "deployer ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload php8.2-fpm"
}

run_test_suite "Cross-Environment System Library (mbf::system::*)"
