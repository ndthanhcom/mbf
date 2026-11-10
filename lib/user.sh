#!/usr/bin/env bash
# mbf:requires log exec config
# ==============================================================================
# mbf core library: user
# Linux user/group creation, SSH authorized_keys management, and sudoers setup
# ==============================================================================

# Return 0 if system user exists
function mbf::user::exists() {
    id -u "$1" >/dev/null 2>&1
}

# Idempotently create a system/login user with home directory and shell
# Usage: mbf::user::ensure <username> [home_dir] [shell]
function mbf::user::ensure() {
    local username="$1"
    local home_dir="${2:-/home/$username}"
    local shell="${3:-/bin/bash}"

    if mbf::user::exists "$username"; then
        mbf::log::info "User '$username' already exists"
        return 0
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would create user '$username' (home: $home_dir, shell: $shell)"
        return 0
    fi

    mbf::exec::sudo useradd -m -d "$home_dir" -s "$shell" "$username"
}

# Idempotently add an SSH public key to a user's `~/.ssh/authorized_keys` (or custom path)
# Usage: mbf::user::add_ssh_key <username> "<ssh_pubkey>" [custom_auth_keys_file]
function mbf::user::add_ssh_key() {
    local username="$1"
    local pubkey="$2"
    local auth_file="${3:-}"

    if [ -z "$auth_file" ]; then
        local home_dir
        home_dir="$(eval echo "~$username" 2>/dev/null || echo "/home/$username")"
        auth_file="${home_dir}/.ssh/authorized_keys"
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would add SSH key for '$username' to $auth_file"
        return 0
    fi

    local ssh_dir
    ssh_dir="$(dirname "$auth_file")"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    mbf::config::ensure "$auth_file" "$pubkey"
    chmod 600 "$auth_file"

    if [ "$(id -u)" == "0" ] && mbf::user::exists "$username"; then
        chown -R "${username}:${username}" "$ssh_dir"
    fi
}

# Remove an SSH key matching `<pattern>` from a user's `authorized_keys`
function mbf::user::remove_ssh_key() {
    local username="$1"
    local pattern="$2"
    local auth_file="${3:-/home/${username}/.ssh/authorized_keys}"

    [ -f "$auth_file" ] || return 0
    mbf::config::delete_line "$auth_file" "$pattern"
}

# Configure passwordless sudo for a user (optionally restricted to specific commands)
# Usage: mbf::user::set_sudo_nopasswd <username> [cmd_list] [sudoers_dir]
function mbf::user::set_sudo_nopasswd() {
    local username="$1"
    local cmds="${2:-ALL}"
    local sudoers_dir="${3:-/etc/sudoers.d}"
    local sudoers_file="${sudoers_dir}/${username}"
    local rule="${username} ALL=(ALL) NOPASSWD: ${cmds}"

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would write sudoers rule '$rule' to $sudoers_file"
        return 0
    fi

    mkdir -p "$sudoers_dir"
    printf '%s\n' "$rule" > "$sudoers_file"
    chmod 0440 "$sudoers_file"
}
