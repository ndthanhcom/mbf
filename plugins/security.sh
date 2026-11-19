#!/usr/bin/env bash
# @mbf-module: security
# mbf:requires log exec system config
# ==============================================================================
# mbf plugin: security
# Automated Server Security Audit, SSH/Fail2ban Hardening & Firewall Management
# ==============================================================================

# Read effective sshd directive across `<sshd_config>.d/*.conf` drop-ins and `<sshd_config>`.
# OpenSSH uses FIRST-match-wins semantics, and Ubuntu 22.04+ includes `sshd_config.d/*.conf`
# at the top of `/etc/ssh/sshd_config`.
function _mbf_security_sshd_effective() {
    local sshd_conf="$1"
    local directive="$2"
    local dropin_dir="${sshd_conf}.d"
    local f val

    if [ -d "$dropin_dir" ]; then
        for f in "$dropin_dir"/*.conf; do
            [ -r "$f" ] || continue
            if val="$(mbf::config::get_directive "$f" "$directive")"; then
                printf '%s\n' "$val"
                return 0
            fi
        done
    fi
    mbf::config::get_directive "$sshd_conf" "$directive"
}

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
    root_login="$(_mbf_security_sshd_effective "$sshd_conf" "PermitRootLogin" || true)"
    pass_auth="$(_mbf_security_sshd_effective "$sshd_conf" "PasswordAuthentication" || true)"
    empty_pass="$(_mbf_security_sshd_effective "$sshd_conf" "PermitEmptyPasswords" || true)"
    port="$(_mbf_security_sshd_effective "$sshd_conf" "Port" || true)"

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

# Safely set an OpenSSH directive in `<file>` without corrupting prose comments.
# - Active directive lines (`^[[:space:]]*<key>[[:space:]]+...`, case-insensitive):
#   replaces the first active line and drops duplicate active lines for `<key>`.
# - Else, single-value commented defaults (`^[[:space:]]*#[[:space:]]*<key>[[:space:]]+[^[:space:]]+[[:space:]]*$`):
#   uncomments and updates the first match, leaving explanatory comments untouched.
# - Else, appends `<key> <value>` at the end of `<file>`.
function _mbf_security_set_sshd_directive() {
    local file="$1"
    local key="$2"
    local value="$3"
    [ -f "$file" ] || return 1
    mbf::is_dryrun && return 0

    MBF_K="$key" MBF_V="$value" awk '
        BEGIN {
            k = ENVIRON["MBF_K"]
            kl = tolower(k)
            v = ENVIRON["MBF_V"]
            has_active = 0
            n = 0
        }
        {
            lines[++n] = $0
            if ($0 !~ /^[ \t]*#/ && tolower($1) == kl && NF >= 2) {
                has_active = 1
            }
        }
        END {
            done = 0
            for (i = 1; i <= n; i++) {
                line = lines[i]
                if (has_active) {
                    tmp = line
                    sub(/^[ \t]+/, "", tmp)
                    if (substr(tmp, 1, 1) != "#") {
                        split(tmp, parts, /[ \t]+/)
                        if (tolower(parts[1]) == kl && length(parts[2]) > 0) {
                            if (!done) {
                                print k " " v
                                done = 1
                            }
                            continue
                        }
                    }
                    print line
                } else {
                    # Match commented default directive like `#PermitRootLogin prohibit-password`
                    # (exactly 2 whitespace-separated tokens after `#`), never prose comments
                    if (!done && line ~ /^[ \t]*#/) {
                        tmp = line
                        sub(/^[ \t]*#[ \t]*/, "", tmp)
                        sub(/[ \t]+$/, "", tmp)
                        cnt = split(tmp, parts, /[ \t]+/)
                        if (cnt == 2 && tolower(parts[1]) == kl) {
                            print k " " v
                            done = 1
                            continue
                        }
                    }
                    print line
                }
            }
            if (!done) {
                print k " " v
            }
        }
    ' "$file" | _mbf_replace_file "$file"
}

# Harden SSH configuration safely with backup, drop-in neutralization, and `sshd -t` validation
# Usage: mbf::security::harden_ssh [sshd_config_file] [disable_password_auth:0|1]
function mbf::security::harden_ssh() {
    local sshd_conf="${1:-/etc/ssh/sshd_config}"
    local disable_pass="${2:-1}"

    if [ ! -f "$sshd_conf" ]; then
        mbf::log::error "mbf::security::harden_ssh: $sshd_conf not found"
        return 1
    fi

    mbf::config::backup "$sshd_conf"

    _mbf_security_set_sshd_directive "$sshd_conf" "PermitRootLogin" "no"
    _mbf_security_set_sshd_directive "$sshd_conf" "PermitEmptyPasswords" "no"

    if [ "$disable_pass" == "1" ]; then
        _mbf_security_set_sshd_directive "$sshd_conf" "PasswordAuthentication" "no"
        # Also update any drop-in configs in `<sshd_config>.d/*.conf` (e.g. cloud-init)
        if [ -d "${sshd_conf}.d" ]; then
            local df
            for df in "${sshd_conf}.d"/*.conf; do
                [ -f "$df" ] || continue
                if mbf::config::get_directive "$df" "PasswordAuthentication" >/dev/null 2>&1; then
                    _mbf_security_set_sshd_directive "$df" "PasswordAuthentication" "no"
                fi
            done
        fi
    fi

    if ! mbf::is_dryrun && command -v sshd >/dev/null 2>&1 && [ "$sshd_conf" == "/etc/ssh/sshd_config" ]; then
        if ! sshd -t -f "$sshd_conf" 2>/dev/null; then
            mbf::log::error "sshd configuration test failed; rolling back"
            mbf::config::rollback "$sshd_conf"
            return 1
        fi
        mbf::system::service reload sshd 2>/dev/null || mbf::system::service reload ssh 2>/dev/null || true
    fi

    mbf::log::ok "SSH configuration hardened ($sshd_conf)"
    return 0
}

# Install and start fail2ban service
function mbf::security::install_fail2ban() {
    mbf::system::pkg_install fail2ban || return 1
    mbf::system::service_ensure fail2ban
}

# Detect active or installed firewall backend (ufw, firewalld, iptables)
function mbf::security::fw_backend() {
    if [ -n "${MBF_FIREWALL_BACKEND:-}" ]; then
        printf '%s\n' "$MBF_FIREWALL_BACKEND"
        return 0
    elif command -v ufw >/dev/null 2>&1; then
        printf 'ufw\n'
    elif command -v firewall-cmd >/dev/null 2>&1; then
        printf 'firewalld\n'
    elif command -v iptables >/dev/null 2>&1; then
        printf 'iptables\n'
    else
        printf 'none\n'
        return 1
    fi
}

# Allow incoming traffic on a port/protocol (idempotent on ufw, firewalld, and iptables)
# Usage: mbf::security::fw_allow <port> [tcp|udp]
function mbf::security::fw_allow() {
    local port="$1"
    local proto="${2:-tcp}"
    local backend
    backend="$(mbf::security::fw_backend || echo none)"

    case "$backend" in
        ufw)
            mbf::system::as_root ufw allow "${port}/${proto}"
            ;;
        firewalld)
            mbf::system::as_root firewall-cmd --permanent --add-port="${port}/${proto}" && \
                mbf::system::as_root firewall-cmd --reload
            ;;
        iptables)
            if ! mbf::is_dryrun && iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; then
                return 0
            fi
            mbf::system::as_root iptables -A INPUT -p "$proto" --dport "$port" -j ACCEPT
            ;;
        *)
            mbf::log::error "No supported firewall backend found"
            return 1
            ;;
    esac
}

# Deny incoming traffic on a port/protocol
# Note: On `firewalld` this removes the port from the zone's allowed ports list;
# on `ufw` and `iptables` it adds an explicit deny/DROP rule (idempotent).
# Usage: mbf::security::fw_deny <port> [tcp|udp]
function mbf::security::fw_deny() {
    local port="$1"
    local proto="${2:-tcp}"
    local backend
    backend="$(mbf::security::fw_backend || echo none)"

    case "$backend" in
        ufw)
            mbf::system::as_root ufw deny "${port}/${proto}"
            ;;
        firewalld)
            mbf::system::as_root firewall-cmd --permanent --remove-port="${port}/${proto}" && \
                mbf::system::as_root firewall-cmd --reload
            ;;
        iptables)
            if ! mbf::is_dryrun && iptables -C INPUT -p "$proto" --dport "$port" -j DROP 2>/dev/null; then
                return 0
            fi
            mbf::system::as_root iptables -A INPUT -p "$proto" --dport "$port" -j DROP
            ;;
        *)
            mbf::log::error "No supported firewall backend found"
            return 1
            ;;
    esac
}

# Enable safe baseline firewall rules (always allowing SSH + HTTP/HTTPS first to prevent lockout)
# Usage: mbf::security::fw_enable_baseline [ssh_port]
function mbf::security::fw_enable_baseline() {
    local ssh_port="${1:-22}"
    local backend
    backend="$(mbf::security::fw_backend || echo none)"

    mbf::security::fw_allow "$ssh_port" "tcp" || return 1
    mbf::security::fw_allow "80" "tcp" || return 1
    mbf::security::fw_allow "443" "tcp" || return 1

    if [ "$backend" == "ufw" ]; then
        mbf::system::as_root ufw default deny incoming
        mbf::system::as_root ufw default allow outgoing
        mbf::system::as_root ufw --force enable
    fi
    mbf::log::ok "Baseline firewall rules enabled (SSH:$ssh_port, HTTP:80, HTTPS:443)"
}
