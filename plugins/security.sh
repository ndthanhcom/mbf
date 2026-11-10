#!/usr/bin/env bash
# mbf:requires log config template service os
# ==============================================================================
# mbf plugin: security
# Automated Server Security Audit & Baseline SSH / Fail2ban Hardening
# ==============================================================================

# Audit SSH daemon configuration for common security risks
# Usage: mbf::security::audit_ssh [sshd_config_file]
function mbf::security::audit_ssh() {
    local sshd_conf="${1:-/etc/ssh/sshd_config}"
    printf '\n=== SSH SECURITY AUDIT (%s) ===\n' "$sshd_conf"

    if [ ! -r "$sshd_conf" ]; then
        printf 'sshd_config not readable: %s\n' "$sshd_conf"
        return 1
    fi

    local root_login pass_auth empty_pass port
    root_login="$(grep -iE '^[[:space:]]*PermitRootLogin[[:space:]]+' "$sshd_conf" | tail -n1 | awk '{print $2}')"
    pass_auth="$(grep -iE '^[[:space:]]*PasswordAuthentication[[:space:]]+' "$sshd_conf" | tail -n1 | awk '{print $2}')"
    empty_pass="$(grep -iE '^[[:space:]]*PermitEmptyPasswords[[:space:]]+' "$sshd_conf" | tail -n1 | awk '{print $2}')"
    port="$(grep -iE '^[[:space:]]*Port[[:space:]]+' "$sshd_conf" | tail -n1 | awk '{print $2}')"

    printf 'Port                   : %s\n' "${port:-22 (default)}"
    printf 'PermitRootLogin        : %s\n' "${root_login:-unset (check default)}"
    printf 'PasswordAuthentication : %s\n' "${pass_auth:-unset (check default)}"
    printf 'PermitEmptyPasswords   : %s\n' "${empty_pass:-no}"

    if [ "${root_login,,}" == "yes" ]; then
        printf '[RISK] PermitRootLogin is enabled\n'
    fi
    if [ "${pass_auth,,}" == "yes" ]; then
        printf '[WARN] PasswordAuthentication is enabled (SSH key-only recommended)\n'
    fi
}

# Audit system accounts, sudoers, and security services
# Usage: mbf::security::audit_system [passwd_file]
function mbf::security::audit_system() {
    local passwd_file="${1:-/etc/passwd}"
    printf '\n=== SYSTEM SECURITY AUDIT ===\n'

    if [ -r "$passwd_file" ]; then
        local uid0_users
        uid0_users="$(awk -F: '$3 == 0 {print $1}' "$passwd_file" | tr '\n' ' ')"
        printf 'UID 0 Accounts         : %s\n' "$uid0_users"
    fi

    if command -v fail2ban-client >/dev/null 2>&1; then
        printf 'Fail2banInstalled     : yes\n'
    else
        printf 'Fail2banInstalled     : no\n'
    fi
}

# Harden SSH configuration safely with backup and `sshd -t` validation
# Usage: mbf::security::harden_ssh [sshd_config_file] [disable_password_auth:0|1]
function mbf::security::harden_ssh() {
    local sshd_conf="${1:-/etc/ssh/sshd_config}"
    local disable_pass="${2:-1}"

    if [ ! -f "$sshd_conf" ]; then
        mbf::log::error "mbf::security::harden_ssh: $sshd_conf not found"
        return 1
    fi

    mbf::template::backup "$sshd_conf"

    if grep -qiE '^[[:space:]]*#?[[:space:]]*PermitRootLogin' "$sshd_conf"; then
        mbf::config::replace_line "$sshd_conf" "PermitRootLogin" "PermitRootLogin no"
    else
        mbf::config::insert "$sshd_conf" "PermitRootLogin no"
    fi

    if grep -qiE '^[[:space:]]*#?[[:space:]]*PermitEmptyPasswords' "$sshd_conf"; then
        mbf::config::replace_line "$sshd_conf" "PermitEmptyPasswords" "PermitEmptyPasswords no"
    else
        mbf::config::insert "$sshd_conf" "PermitEmptyPasswords no"
    fi

    if [ "$disable_pass" == "1" ]; then
        if grep -qiE '^[[:space:]]*#?[[:space:]]*PasswordAuthentication' "$sshd_conf"; then
            mbf::config::replace_line "$sshd_conf" "PasswordAuthentication" "PasswordAuthentication no"
        else
            mbf::config::insert "$sshd_conf" "PasswordAuthentication no"
        fi
    fi

    if ! mbf::is_dryrun && command -v sshd >/dev/null 2>&1 && [ "$sshd_conf" == "/etc/ssh/sshd_config" ]; then
        if ! sshd -t -f "$sshd_conf" 2>/dev/null; then
            mbf::log::error "sshd configuration test failed; rolling back"
            mbf::template::rollback "$sshd_conf"
            return 1
        fi
        mbf::service::reload sshd 2>/dev/null || mbf::service::reload ssh 2>/dev/null || true
    fi

    mbf::log::ok "SSH configuration hardened ($sshd_conf)"
    return 0
}

# Install and start fail2ban service
function mbf::security::install_fail2ban() {
    mbf::os::pkg_install fail2ban || return 1
    mbf::service::ensure_running fail2ban
}
