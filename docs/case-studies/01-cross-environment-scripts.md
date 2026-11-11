# Case Study 1: Cross-Environment Scripts (Linux, macOS, Windows Git Bash, WSL & Android Termux)

## Problem Statement
Standard Bash scripts break when moved between a Linux VPS, a developer's macOS laptop, a Windows workstation running Git Bash (`MSYS2`/`MINGW64`), or an Android device running Termux:
- **Privilege Escalation**: `sudo` is required on non-root Linux/macOS, but `sudo` does not exist on Windows Git Bash and is forbidden when running `pkg` on Android Termux.
- **Filesystem Prefixes**: Hardcoded `/etc` or `/usr/local/bin` paths fail on Termux, where root filesystem paths live under `$PREFIX` (`/data/data/com.termux/files/usr/etc`).
- **Package Managers**: Installing a tool like `jq`, `curl`, or `git` requires `apt-get`/`dnf`/`apk`/`pacman` on Linux, `brew` on macOS, `pkg` on Termux, and `winget`/`choco` on Windows.

---

## MBF Architecture & Solution

`mbf` solves cross-environment portability in `lib/system.sh` (`mbf::system::*`) using three abstractions:

1. **`mbf::system::env_type`**: Detects `linux`, `wsl`, `macos`, `gitbash`, or `termux`.
2. **`mbf::system::prefix` & `mbf::system::as_root`**:
   - `mbf::system::prefix` returns `$PREFIX` on Termux and empty string on standard systems so `$(mbf::system::prefix)/etc` always points to the writable configuration root.
   - `mbf::system::as_root <cmd>` skips `sudo` when `EUID == 0` or on `termux`/`gitbash`, and uses `mbf::exec::sudo` on non-root Linux/macOS.
3. **`mbf::system::pkg_install`**: Dispatches package installation to `pkg` (Termux), `apt-get`/`dnf`/`yum`/`apk`/`pacman`/`zypper` (Linux), `brew` (macOS), or `winget`/`choco` (Windows Git Bash).

---

## Complete Blueprint Script (`bootstrap-dev-env.sh`)

```bash
#!/usr/bin/env bash
source "${MBF_HOME:-$(dirname "$(command -v mbf)")/..}/framework.sh"
mbf::use log args exec system config

USAGE="Usage: $(basename "$0") [--dry-run] [--profile <minimal|full>]"
mbf::args::flag   "n" "dry-run" "MBF_DRYRUN"  "Preview changes without modifying system"
mbf::args::option "p" "profile" "OPT_PROFILE" "Environment profile (minimal|full)" "minimal"

function main() {
    mbf::args::parse "$@" || return 1

    local env_type sys_prefix etc_dir
    env_type="$(mbf::system::env_type)"
    sys_prefix="$(mbf::system::prefix)"
    etc_dir="${sys_prefix}/etc"

    mbf::log::info "Detected environment: ${env_type} (arch: $(mbf::system::arch), pkg: $(mbf::system::pkg_manager))"

    # 1. Install core CLI utilities across Linux, macOS, Git Bash, or Termux
    local -a base_pkgs=(git curl jq)
    [ "$OPT_PROFILE" == "full" ] && base_pkgs+=(tmux ripgrep)

    mbf::system::pkg_install "${base_pkgs[@]}" || return 1

    # 2. Configure user shell profile idempotently
    local rc_file="${HOME}/.bashrc"
    [ "$env_type" == "macos" ] && rc_file="${HOME}/.zshrc"

    mbf::config::ensure_block "$rc_file" "dev_aliases" \
'export EDITOR="vim"
alias ll="ls -la"
alias gs="git status"'

    # 3. Environment-specific adjustments
    case "$env_type" in
        termux)
            mbf::log::info "Termux detected: using config directory ${etc_dir}"
            ;;
        gitbash)
            mbf::exec::run git config --global core.autocrlf input
            ;;
        linux|wsl)
            mbf::log::info "Linux/WSL environment ready"
            ;;
    esac

    mbf::log::ok "Environment bootstrap completed for ${env_type}."
}

main "$@"
```
