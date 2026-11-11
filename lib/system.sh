#!/usr/bin/env bash
# @mbf-module: system
# @mbf-rank: •••
# mbf:requires log exec config
# ==============================================================================
# mbf core library: system
# Cross-environment detection (Linux, macOS, Git Bash, WSL, Termux),
# unified package manager, service controller, user/SSH setup & pre-flight checks
# ==============================================================================

# Detect runtime environment type: termux, wsl, gitbash, macos, linux, or unknown
function mbf::system::env_type() {
    if [ -n "${MBF_ENV_TYPE_OVERRIDE:-}" ]; then
        printf '%s\n' "$MBF_ENV_TYPE_OVERRIDE"
        return 0
    fi
    if [ -n "${TERMUX_VERSION:-}" ] || [[ "${PREFIX:-}" == *"com.termux"* ]]; then
        printf 'termux\n'
        return 0
    fi
    local os_s
    os_s="$(uname -s 2>/dev/null || echo unknown)"
    case "$os_s" in
        MINGW*|MSYS*|CYGWIN*)
            printf 'gitbash\n'
            ;;
        Darwin*)
            printf 'macos\n'
            ;;
        Linux*)
            if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
                printf 'wsl\n'
            else
                printf 'linux\n'
            fi
            ;;
        *)
            printf 'unknown\n'
            ;;
    esac
}

# Print filesystem root prefix (returns $PREFIX on Android Termux, empty otherwise)
function mbf::system::prefix() {
    if [ "$(mbf::system::env_type)" == "termux" ]; then
        printf '%s\n' "${PREFIX:-/data/data/com.termux/files/usr}"
    else
        printf '\n'
    fi
}

# Run a command with root privileges where appropriate (skips sudo on Termux/GitBash or EUID 0)
function mbf::system::as_root() {
    local env_t
    env_t="$(mbf::system::env_type)"
    if [ "$(id -u)" == "0" ] || [ "$env_t" == "termux" ] || [ "$env_t" == "gitbash" ]; then
        mbf::exec::run "$@"
    else
        mbf::exec::sudo "$@"
    fi
}

# Detect OS / Linux distribution ID (e.g. ubuntu, debian, rocky, rhel, alpine, macos, termux, gitbash)
function mbf::system::distro() {
    local env_t
    env_t="$(mbf::system::env_type)"
    if [ "$env_t" == "termux" ] || [ "$env_t" == "gitbash" ] || [ "$env_t" == "macos" ]; then
        printf '%s\n' "$env_t"
        return 0
    fi
    if [ -r /etc/os-release ]; then
        awk -F= '/^ID=/ {gsub(/["'\'']/, "", $2); print tolower($2); exit}' /etc/os-release
        return 0
    fi
    printf '%s\n' "$env_t"
}

# Detect OS version ID (e.g. 22.04, 12, 9)
function mbf::system::version() {
    if [ -r /etc/os-release ]; then
        awk -F= '/^VERSION_ID=/ {gsub(/["'\'']/, "", $2); print $2; exit}' /etc/os-release
        return 0
    fi
    uname -r 2>/dev/null || printf 'unknown\n'
}

# Normalize CPU architecture (amd64, arm64, armv7, etc.)
function mbf::system::arch() {
    local m
    m="$(uname -m 2>/dev/null || echo unknown)"
    case "$m" in
        x86_64|amd64)   printf 'amd64\n' ;;
        aarch64|arm64)  printf 'arm64\n' ;;
        armv7l|armv7)   printf 'armv7\n' ;;
        *)              printf '%s\n' "$m" ;;
    esac
}

# Detect primary OS package manager (supports Termux pkg, Linux, macOS, Windows)
function mbf::system::pkg_manager() {
    if [ "$(mbf::system::env_type)" == "termux" ] && command -v pkg >/dev/null 2>&1; then
        printf 'pkg\n'
        return 0
    fi
    local pm
    for pm in apt-get dnf yum apk pacman zypper brew winget choco pkg; do
        if command -v "$pm" >/dev/null 2>&1; then
            printf '%s\n' "$pm"
            return 0
        fi
    done
    printf 'unknown\n'
    return 1
}

# Update OS package manager index
function mbf::system::pkg_update() {
    local pm
    pm="$(mbf::system::pkg_manager)"
    case "$pm" in
        pkg)     mbf::exec::run pkg update -y ;;
        apt-get) DEBIAN_FRONTEND=noninteractive mbf::system::as_root apt-get update -qq ;;
        dnf)     mbf::system::as_root dnf makecache -q ;;
        yum)     mbf::system::as_root yum makecache -q ;;
        apk)     mbf::system::as_root apk update -q ;;
        pacman)  mbf::system::as_root pacman -Sy --noconfirm ;;
        brew)    mbf::exec::run brew update ;;
        *)       mbf::log::warn "pkg_update not supported for '$pm'"; return 1 ;;
    esac
}

# Install one or more OS packages idempotently across environments
# Usage: mbf::system::pkg_install nginx curl jq
function mbf::system::pkg_install() {
    [ $# -eq 0 ] && return 0
    local pm
    pm="$(mbf::system::pkg_manager)"
    case "$pm" in
        pkg)     mbf::exec::run pkg install -y "$@" ;;
        apt-get) DEBIAN_FRONTEND=noninteractive mbf::system::as_root apt-get install -y -qq "$@" ;;
        dnf)     mbf::system::as_root dnf install -y -q "$@" ;;
        yum)     mbf::system::as_root yum install -y -q "$@" ;;
        apk)     mbf::system::as_root apk add --no-cache "$@" ;;
        pacman)  mbf::system::as_root pacman -S --noconfirm "$@" ;;
        zypper)  mbf::system::as_root zypper install -y "$@" ;;
        brew)    mbf::exec::run brew install "$@" ;;
        winget)  mbf::exec::run winget install --accept-source-agreements --accept-package-agreements "$@" ;;
        choco)   mbf::exec::run choco install -y "$@" ;;
        *)       mbf::log::error "Unsupported package manager '$pm' to install: $*"; return 1 ;;
    esac
}

# Check if a package is installed in the system package database
function mbf::system::pkg_is_installed() {
    local pkg="$1"
    if command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -Fq "install ok installed"
    elif command -v rpm >/dev/null 2>&1; then
        rpm -q "$pkg" >/dev/null 2>&1
    elif command -v apk >/dev/null 2>&1; then
        apk info -e "$pkg" >/dev/null 2>&1
    else
        command -v "$pkg" >/dev/null 2>&1
    fi
}

# Unified system service controller (start, stop, restart, reload, enable)
# Usage: mbf::system::service <start|stop|restart|reload|enable> <service_name>
function mbf::system::service() {
    local action="$1"
    local svc="$2"

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would $action service '$svc'"
        return 0
    fi

    if [ "$action" == "enable" ]; then
        if command -v systemctl >/dev/null 2>&1; then
            mbf::system::as_root systemctl enable "$svc"
        elif command -v rc-update >/dev/null 2>&1; then
            mbf::system::as_root rc-update add "$svc" default
        fi
        return 0
    fi

    if command -v systemctl >/dev/null 2>&1; then
        mbf::system::as_root systemctl "$action" "$svc"
    elif command -v service >/dev/null 2>&1; then
        mbf::system::as_root service "$svc" "$action"
    elif command -v rc-service >/dev/null 2>&1; then
        mbf::system::as_root rc-service "$svc" "$action"
    elif command -v sv >/dev/null 2>&1; then
        mbf::exec::run sv "$action" "$svc"
    else
        mbf::log::error "No supported service manager (systemctl/service/rc-service/sv) found"
        return 1
    fi
}

# Return 0 if service is currently active/running
function mbf::system::service_is_active() {
    local svc="$1"
    mbf::is_dryrun && return 0
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet "$svc"
    elif command -v service >/dev/null 2>&1; then
        service "$svc" status >/dev/null 2>&1
    else
        pgrep -x "$svc" >/dev/null 2>&1
    fi
}

# Ensure service is enabled and running (starts it if stopped)
function mbf::system::service_ensure() {
    local svc="$1"
    mbf::system::service enable "$svc"
    if ! mbf::system::service_is_active "$svc"; then
        mbf::system::service start "$svc"
    fi
}

# Return 0 if system user exists
function mbf::system::user_exists() {
    id -u "$1" >/dev/null 2>&1
}

# Idempotently create a system/login user with home directory and shell
# Usage: mbf::system::user_ensure <username> [home_dir] [shell]
function mbf::system::user_ensure() {
    local username="$1"
    local home_dir="${2:-/home/$username}"
    local shell="${3:-/bin/bash}"

    if mbf::system::user_exists "$username"; then
        mbf::log::info "User '$username' already exists"
        return 0
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would create user '$username' (home: $home_dir, shell: $shell)"
        return 0
    fi

    mbf::system::as_root useradd -m -d "$home_dir" -s "$shell" "$username"
}

# Idempotently add an SSH public key to a user's `~/.ssh/authorized_keys` (or custom path)
# Usage: mbf::system::ssh_key_add <username> "<ssh_pubkey>" [custom_auth_keys_file]
function mbf::system::ssh_key_add() {
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

    if [ "$(id -u)" == "0" ] && mbf::system::user_exists "$username"; then
        chown -R "${username}:${username}" "$ssh_dir"
    fi
}

# Remove an SSH key matching `<pattern>` from a user's `authorized_keys`
function mbf::system::ssh_key_remove() {
    local username="$1"
    local pattern="$2"
    local auth_file="${3:-/home/${username}/.ssh/authorized_keys}"

    [ -f "$auth_file" ] || return 0
    mbf::config::delete_line "$auth_file" "$pattern"
}

# Configure passwordless sudo for a user (optionally restricted to specific commands)
# Usage: mbf::system::sudo_nopasswd <username> [cmd_list] [sudoers_dir]
function mbf::system::sudo_nopasswd() {
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

# Check if a command exists in PATH (and optionally matches expected version)
# Usage: mbf::system::check_cmd <cmd_name> [expected_version]
function mbf::system::check_cmd() {
    local cmd_name="$1"
    local expected_ver="${2:-}"

    if ! command -v "$cmd_name" >/dev/null 2>&1; then
        mbf::log::warn "Required program '$cmd_name' is not installed."
        return 1
    fi

    if [ -n "$expected_ver" ]; then
        local actual_ver
        actual_ver="$("$cmd_name" --version 2>/dev/null | head -n 1 | awk '{print $NF}')"
        if [ "$actual_ver" != "$expected_ver" ]; then
            mbf::log::error "Program '$cmd_name' version '$expected_ver' required (found: '$actual_ver')."
            return 1
        fi
    fi
    return 0
}

# Verify multiple commands are installed (or check $MBF_REQUIREMENTS if no args given)
function mbf::system::check_cmds() {
    local -a list=("$@")
    if [ "${#list[@]}" -eq 0 ] && [ -n "${MBF_REQUIREMENTS:-}" ]; then
        read -r -a list <<< "$MBF_REQUIREMENTS"
    fi

    local cmd
    for cmd in "${list[@]}"; do
        mbf::system::check_cmd "$cmd" || return 1
    done
    return 0
}

# Verify one or more environment variables are set and non-empty
function mbf::system::check_env() {
    local var_name
    for var_name in "$@"; do
        if [ -z "${!var_name:-}" ]; then
            mbf::log::error "Required environment variable '$var_name' is not set."
            return 1
        fi
    done
    return 0
}

# Validate alphanumeric + underscore identifier
function mbf::system::is_alnum() {
    [[ -n "${1:-}" && "$1" =~ ^[a-zA-Z0-9_]+$ ]]
}

# Validate domain name syntax
function mbf::system::is_domain() {
    [[ -n "${1:-}" && "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

# Validate IPv4 address syntax and octet range
function mbf::system::is_ip() {
    local ip="${1:-}"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS='.' oct
    for oct in $ip; do
        [ "$oct" -le 255 ] 2>/dev/null || return 1
    done
    return 0
}

# Validate email address syntax
function mbf::system::is_email() {
    [[ -n "${1:-}" && "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}
