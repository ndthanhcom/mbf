#!/usr/bin/env bash
# mbf:requires log exec
# ==============================================================================
# mbf core library: os
# Distro, version, CPU architecture, and unified OS package manager interface
# ==============================================================================

# Detect OS / Linux distribution ID (e.g. ubuntu, debian, rocky, rhel, alpine, macos)
function mbf::os::distro() {
    if [ -r /etc/os-release ]; then
        awk -F= '/^ID=/ {gsub(/["'\'']/, "", $2); print tolower($2); exit}' /etc/os-release
        return 0
    fi
    case "$(uname -s 2>/dev/null)" in
        Darwin) printf 'macos\n' ;;
        Linux)  printf 'linux\n' ;;
        *)      printf 'unknown\n' ;;
    esac
}

# Detect OS version ID (e.g. 22.04, 12, 9)
function mbf::os::version() {
    if [ -r /etc/os-release ]; then
        awk -F= '/^VERSION_ID=/ {gsub(/["'\'']/, "", $2); print $2; exit}' /etc/os-release
        return 0
    fi
    uname -r 2>/dev/null || printf 'unknown\n'
}

# Normalize CPU architecture (amd64, arm64, armv7, etc.)
function mbf::os::arch() {
    local m
    m="$(uname -m 2>/dev/null || echo unknown)"
    case "$m" in
        x86_64|amd64)   printf 'amd64\n' ;;
        aarch64|arm64)  printf 'arm64\n' ;;
        armv7l|armv7)   printf 'armv7\n' ;;
        *)              printf '%s\n' "$m" ;;
    esac
}

# Detect primary OS package manager
function mbf::os::pkg_manager() {
    local pm
    for pm in apt-get dnf yum apk pacman zypper brew winget choco; do
        if command -v "$pm" >/dev/null 2>&1; then
            printf '%s\n' "$pm"
            return 0
        fi
    done
    printf 'unknown\n'
    return 1
}

# Update OS package manager index
function mbf::os::pkg_update() {
    local pm
    pm="$(mbf::os::pkg_manager)"
    case "$pm" in
        apt-get) DEBIAN_FRONTEND=noninteractive mbf::exec::sudo apt-get update -qq ;;
        dnf)     mbf::exec::sudo dnf makecache -q ;;
        yum)     mbf::exec::sudo yum makecache -q ;;
        apk)     mbf::exec::sudo apk update -q ;;
        pacman)  mbf::exec::sudo pacman -Sy --noconfirm ;;
        brew)    mbf::exec::run brew update ;;
        *)       mbf::log::warn "pkg_update not supported for '$pm'"; return 1 ;;
    esac
}

# Install one or more OS packages idempotently
# Usage: mbf::os::pkg_install nginx curl jq
function mbf::os::pkg_install() {
    [ $# -eq 0 ] && return 0
    local pm
    pm="$(mbf::os::pkg_manager)"
    case "$pm" in
        apt-get) DEBIAN_FRONTEND=noninteractive mbf::exec::sudo apt-get install -y -qq "$@" ;;
        dnf)     mbf::exec::sudo dnf install -y -q "$@" ;;
        yum)     mbf::exec::sudo yum install -y -q "$@" ;;
        apk)     mbf::exec::sudo apk add --no-cache "$@" ;;
        pacman)  mbf::exec::sudo pacman -S --noconfirm "$@" ;;
        zypper)  mbf::exec::sudo zypper install -y "$@" ;;
        brew)    mbf::exec::run brew install "$@" ;;
        *)       mbf::log::error "Unsupported package manager '$pm' to install: $*"; return 1 ;;
    esac
}

# Check if a package is installed in the system package database
function mbf::os::pkg_is_installed() {
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
