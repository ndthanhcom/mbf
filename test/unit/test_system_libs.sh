#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use os service net user crypto fs

function test_os_and_service_helpers() {
    local arch distro
    arch="$(mbf::os::arch)"
    distro="$(mbf::os::distro)"
    assert_ne "" "$arch"
    assert_ne "" "$distro"

    MBF_DRYRUN="1"
    local svc_out
    svc_out="$(mbf::service::restart "nginx")"
    assert_contains "$svc_out" "Would restart service 'nginx'"
}

function test_net_and_user_helpers() {
    local work_dir auth_keys sudoers_dir
    mbf::fs::tmpdir work_dir
    auth_keys="${work_dir}/.ssh/authorized_keys"
    sudoers_dir="${work_dir}/sudoers.d"

    mbf::user::add_ssh_key "deploy" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey deploy@host" "$auth_keys"
    mbf::user::add_ssh_key "deploy" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey deploy@host" "$auth_keys"
    assert_eq "1" "$(grep -c "AAAAC3NzaC1lZDI1NTE5AAAAITestKey" "$auth_keys")"

    mbf::user::remove_ssh_key "deploy" "AAAAC3NzaC1lZDI1NTE5AAAAITestKey" "$auth_keys"
    assert_eq "0" "$(grep -c "AAAAC3NzaC1lZDI1NTE5AAAAITestKey" "$auth_keys" || true)"

    mbf::user::set_sudo_nopasswd "deploy" "/usr/sbin/service nginx *" "$sudoers_dir"
    assert_contains "$(cat "${sudoers_dir}/deploy")" "deploy ALL=(ALL) NOPASSWD: /usr/sbin/service nginx *"

    MBF_DRYRUN="1"
    assert_eq "203.0.113.10" "$(mbf::net::public_ip)"
}

function test_crypto_sha256_hmac_and_cert_expiry() {
    local work_dir sample_file hash hmac
    mbf::fs::tmpdir work_dir
    sample_file="${work_dir}/payload.txt"
    printf 'hello-mbf\n' > "$sample_file"

    hash="$(mbf::crypto::sha256 "$sample_file")"
    assert_eq "64" "${#hash}"
    mbf::crypto::verify_sha256 "$sample_file" "$hash"
    assert_eq "0" "$?"

    mbf::crypto::verify_sha256 "$sample_file" "0000000000000000000000000000000000000000000000000000000000000000" >/dev/null 2>&1
    assert_eq "1" "$?"

    if command -v openssl >/dev/null 2>&1; then
        hmac="$(mbf::crypto::hmac_sha256 "my_secret" "job_123:ok")"
        assert_eq "64" "${#hmac}"
    fi
}

run_test_suite "System Primitives: os, service, net, user & crypto"
