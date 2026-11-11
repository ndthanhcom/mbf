#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use system net exec

function test_cross_environment_detection_and_prefix() {
    local current_env arch
    current_env="$(mbf::system::env_type)"
    arch="$(mbf::system::arch)"
    assert_ne "" "$current_env"
    assert_ne "" "$arch"

    # Simulate Android Termux environment
    local termux_env termux_prefix
    termux_env="$(TERMUX_VERSION="0.118.0" mbf::system::env_type)"
    assert_eq "termux" "$termux_env"

    termux_prefix="$(TERMUX_VERSION="0.118.0" PREFIX="/data/data/com.termux/files/usr" mbf::system::prefix)"
    assert_eq "/data/data/com.termux/files/usr" "$termux_prefix"

    # Simulate Windows Git Bash & Linux environments via override
    assert_eq "gitbash" "$(MBF_ENV_TYPE_OVERRIDE="gitbash" mbf::system::distro)"
    assert_eq "macos" "$(MBF_ENV_TYPE_OVERRIDE="macos" mbf::system::distro)"
}

function test_service_controller_and_input_validators() {
    MBF_DRYRUN="1"
    local svc_out
    svc_out="$(mbf::system::service restart "varnish")"
    assert_contains "$svc_out" "Would restart service 'varnish'"
    MBF_DRYRUN="0"

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

    mbf::system::ssh_key_add "deployer" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMagentoDeployKey deployer@ci" "$auth_keys"
    mbf::system::ssh_key_add "deployer" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMagentoDeployKey deployer@ci" "$auth_keys"
    assert_eq "1" "$(grep -c "AAAAC3NzaC1lZDI1NTE5AAAAIMagentoDeployKey" "$auth_keys")"

    mbf::system::ssh_key_remove "deployer" "AAAAC3NzaC1lZDI1NTE5AAAAIMagentoDeployKey" "$auth_keys"
    assert_eq "0" "$(grep -c "AAAAC3NzaC1lZDI1NTE5AAAAIMagentoDeployKey" "$auth_keys" || true)"

    mbf::system::sudo_nopasswd "deployer" "/usr/bin/systemctl reload php8.2-fpm, /usr/bin/systemctl reload nginx" "$sudoers_dir"
    assert_contains "$(cat "${sudoers_dir}/deployer")" "deployer ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload php8.2-fpm"
}

run_test_suite "Cross-Environment System Library (mbf::system::*)"
