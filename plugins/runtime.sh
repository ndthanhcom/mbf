#!/usr/bin/env bash
# @mbf-module: runtime
# @mbf-rank: •
# mbf:requires log exec system net
# ==============================================================================
# mbf plugin: runtime
# Integration with System Packages, Node.js Programs, and Python Programs
# ==============================================================================

# Print OS-specific installation / download instructions for a package
# Usage: mbf::runtime::install_hint <pkg_name> [download_url]
function mbf::runtime::install_hint() {
    local pkg="$1"
    local url="${2:-}"
    local pm
    pm="$(mbf::system::pkg_manager)"

    printf '=== Installation Instructions for "%s" ===\n' "$pkg"
    case "$pm" in
        pkg)     printf '  Run: pkg install -y %s\n' "$pkg" ;;
        apt-get) printf '  Run: sudo apt-get update && sudo apt-get install -y %s\n' "$pkg" ;;
        dnf)     printf '  Run: sudo dnf install -y %s\n' "$pkg" ;;
        yum)     printf '  Run: sudo yum install -y %s\n' "$pkg" ;;
        apk)     printf '  Run: sudo apk add --no-cache %s\n' "$pkg" ;;
        pacman)  printf '  Run: sudo pacman -S --noconfirm %s\n' "$pkg" ;;
        zypper)  printf '  Run: sudo zypper install -y %s\n' "$pkg" ;;
        brew)    printf '  Run: brew install %s\n' "$pkg" ;;
        winget)  printf '  Run: winget install %s\n' "$pkg" ;;
        choco)   printf '  Run: choco install -y %s\n' "$pkg" ;;
        *)       printf '  Install "%s" using your system package manager.\n' "$pkg" ;;
    esac

    if [ -n "$url" ]; then
        printf '  Or download directly from: %s\n' "$url"
    fi
}

# Verify a command/package is installed; print install hint or auto-install when MBF_AUTO_INSTALL=1
# Usage: mbf::runtime::ensure_pkg <pkg_name> [cmd_name] [download_url]
function mbf::runtime::ensure_pkg() {
    local pkg="$1"
    local cmd="${2:-$1}"
    local url="${3:-}"

    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    mbf::log::warn "Required program '$cmd' (package: $pkg) is not installed."
    mbf::runtime::install_hint "$pkg" "$url"

    if [ "${MBF_AUTO_INSTALL:-0}" == "1" ]; then
        mbf::system::pkg_install "$pkg"
        return $?
    fi
    return 1
}

# Download a binary or script from URL and make it executable
# Usage: mbf::runtime::download <url> <dest_path> [expected_sha256]
function mbf::runtime::download() {
    local url="$1"
    local dest="$2"
    local sha="${3:-}"

    mbf::net::download "$url" "$dest" "$sha" || return 1
    mbf::is_dryrun || chmod +x "$dest" 2>/dev/null || true
}

function _mbf_resolve_runtime_file() {
    local target="$1"
    local caller_dir="${MBF_SCRIPT_DIR:-${DIR:-}}"
    if [ -f "$target" ]; then
        printf '%s\n' "$target"
        return 0
    elif [ -n "$caller_dir" ] && [ -f "${caller_dir}/${target}" ]; then
        printf '%s\n' "${caller_dir}/${target}"
        return 0
    fi
    return 1
}

# Check Node.js presence and optional minimum major version
# Usage: mbf::runtime::check_node [min_major_version]
function mbf::runtime::check_node() {
    local min_major="${1:-}"
    local node_bin="${MBF_NODE_BIN:-node}"

    if ! command -v "$node_bin" >/dev/null 2>&1; then
        mbf::log::warn "Node.js ('$node_bin') is not installed."
        mbf::runtime::install_hint "nodejs" "https://nodejs.org/"
        return 1
    fi

    if [ -n "$min_major" ]; then
        local ver_str major_ver
        ver_str="$("$node_bin" -v 2>/dev/null || echo "v0.0.0")"
        major_ver="${ver_str#v}"
        major_ver="${major_ver%%.*}"
        if [ "${major_ver:-0}" -lt "$min_major" ] 2>/dev/null; then
            mbf::log::error "Node.js >= v${min_major} required (found: ${ver_str})."
            mbf::runtime::install_hint "nodejs" "https://nodejs.org/"
            return 1
        fi
    fi
    return 0
}

# Run npm install in target directory if package.json exists
function mbf::runtime::npm_install() {
    local proj_dir="${1:-${MBF_SCRIPT_DIR:-.}}"
    [ -f "${proj_dir}/package.json" ] || { mbf::log::warn "No package.json in '$proj_dir'"; return 1; }
    mbf::runtime::check_node || return 1
    mbf::exec::run npm --prefix "$proj_dir" install
}

# Run a Node.js script interactively or with CLI arguments
# Usage: mbf::runtime::run_node <script.js> [args...]
function mbf::runtime::run_node() {
    local script_arg="$1"
    shift 1 2>/dev/null || true
    local node_bin="${MBF_NODE_BIN:-node}"

    local resolved
    if ! resolved="$(_mbf_resolve_runtime_file "$script_arg")"; then
        mbf::log::error "Node.js script not found: $script_arg"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would execute: $node_bin $resolved $*"
        return 0
    fi

    mbf::runtime::check_node || return 1
    "$node_bin" "$resolved" "$@"
}

function _mbf_find_python() {
    if [ -n "${MBF_PYTHON_BIN:-}" ] && command -v "$MBF_PYTHON_BIN" >/dev/null 2>&1; then
        printf '%s\n' "$MBF_PYTHON_BIN"
        return 0
    elif command -v python3 >/dev/null 2>&1; then
        printf 'python3\n'
        return 0
    elif command -v python >/dev/null 2>&1; then
        printf 'python\n'
        return 0
    fi
    return 1
}

# Check Python 3 presence and optional minimum major version
# Usage: mbf::runtime::check_python [min_major_version]
function mbf::runtime::check_python() {
    local min_ver="${1:-}"
    local py_bin

    if ! py_bin="$(_mbf_find_python)"; then
        mbf::log::warn "Python ('python3' or 'python') is not installed."
        mbf::runtime::install_hint "python3" "https://www.python.org/downloads/"
        return 1
    fi

    if [ -n "$min_ver" ]; then
        local found_ver req_major found_major
        found_ver="$("$py_bin" --version 2>&1 | awk '{print $2}')"
        req_major="${min_ver%%.*}"
        found_major="${found_ver%%.*}"
        if [ "${found_major:-0}" -lt "${req_major:-3}" ] 2>/dev/null; then
            mbf::log::error "Python >= ${min_ver} required (found: ${found_ver})."
            mbf::runtime::install_hint "python3" "https://www.python.org/downloads/"
            return 1
        fi
    fi
    return 0
}

# Install Python packages from requirements.txt
# Usage: mbf::runtime::pip_install [requirements.txt] [venv_dir]
function mbf::runtime::pip_install() {
    local req_file="${1:-requirements.txt}"
    local venv_dir="${2:-}"
    local resolved_req py_bin

    if ! resolved_req="$(_mbf_resolve_runtime_file "$req_file")"; then
        mbf::log::warn "Python requirements file not found: $req_file"
        return 1
    fi
    py_bin="$(_mbf_find_python)" || { mbf::runtime::check_python; return 1; }

    if [ -n "$venv_dir" ]; then
        [ -d "$venv_dir" ] || mbf::exec::run "$py_bin" -m venv "$venv_dir" || return 1
        mbf::exec::run "${venv_dir}/bin/pip" install -r "$resolved_req"
    else
        mbf::exec::run "$py_bin" -m pip install -r "$resolved_req"
    fi
}

# Run a Python script interactively or with CLI arguments
# Usage: mbf::runtime::run_python <script.py> [args...]
function mbf::runtime::run_python() {
    local script_arg="$1"
    shift 1 2>/dev/null || true
    local resolved py_bin

    if ! resolved="$(_mbf_resolve_runtime_file "$script_arg")"; then
        mbf::log::error "Python script not found: $script_arg"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would execute: python3 $resolved $*"
        return 0
    fi

    py_bin="$(_mbf_find_python)" || { mbf::runtime::check_python; return 1; }
    "$py_bin" "$resolved" "$@"
}
