#!/usr/bin/env bash
# ==============================================================================
# mbf module: runtime
# Integration with System Programs, Node.js Programs, and Python Programs
#
# Provides:
#   - runtime_detect_pkg_manager  : Detect OS package manager (apt-get, dnf, yum, apk, pacman, brew)
#   - runtime_install_instruction : Print OS-appropriate install/download instructions for an app
#   - runtime_ensure_pkg          : Verify system app exists; print instruction or auto-install (MBF_AUTO_INSTALL=1)
#   - runtime_download_app        : Download a binary/script from URL and make it executable
#   - runtime_check_node          : Check Node.js availability & minimum major version
#   - runtime_install_npm_deps    : Run npm install for bundled package.json
#   - runtime_run_node            : Execute a Node.js script (interactive or CLI args)
#   - runtime_eval_node           : Execute inline Node.js snippet
#   - runtime_check_python        : Check Python 3 availability & minimum version
#   - runtime_install_pip_deps    : Install Python requirements.txt (with optional venv)
#   - runtime_run_python          : Execute a Python script (interactive or CLI args)
#   - runtime_eval_python         : Execute inline Python snippet
# ==============================================================================

# Detect the system's primary package manager
function runtime_detect_pkg_manager() {
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

# Print clear installation / download instructions for a system program
# Usage: runtime_install_instruction <pkg_name> [download_url]
function runtime_install_instruction() {
    local pkg="$1"
    local url="${2:-}"
    local pm
    pm="$(runtime_detect_pkg_manager)"

    printf '=== Installation Instructions for "%s" ===\n' "$pkg"
    case "$pm" in
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
        printf '    curl -fsSL "%s" -o /usr/local/bin/%s && chmod +x /usr/local/bin/%s\n' "$url" "$pkg" "$pkg"
    fi
}

# Ensure a system program is installed; if missing, print install instruction or auto-install when MBF_AUTO_INSTALL=1
# Usage: runtime_ensure_pkg <pkg_name> [cmd_name] [download_url]
function runtime_ensure_pkg() {
    local pkg="$1"
    local cmd="${2:-$1}"
    local url="${3:-}"

    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    print_with_color "Required system program '$cmd' (package: $pkg) is not installed." "yellow"
    runtime_install_instruction "$pkg" "$url"

    if [ "${MBF_AUTO_INSTALL:-0}" == "1" ]; then
        local pm
        pm="$(runtime_detect_pkg_manager)"
        case "$pm" in
            apt-get) run_cmd "_sudo_required_ apt-get update && _sudo_required_ apt-get install -y $pkg" ;;
            dnf)     run_cmd "_sudo_required_ dnf install -y $pkg" ;;
            yum)     run_cmd "_sudo_required_ yum install -y $pkg" ;;
            apk)     run_cmd "_sudo_required_ apk add --no-cache $pkg" ;;
            pacman)  run_cmd "_sudo_required_ pacman -S --noconfirm $pkg" ;;
            brew)    run_cmd "brew install $pkg" ;;
            *)
                print_with_color "Auto-install not supported for package manager '$pm'." "red"
                return 1
                ;;
        esac
        return $?
    fi

    return 1
}

# Download an executable program or script from a URL
# Usage: runtime_download_app <url> <dest_path>
function runtime_download_app() {
    local url="$1"
    local dest="$2"
    local dryrun="${MBF_DRYRUN:-${I7R_DRYRUN:-0}}"

    if [ -z "$url" ] || [ -z "$dest" ]; then
        log_error "runtime_download_app: <url> and <dest_path> are required"
        return 1
    fi

    if [ "$dryrun" == "1" ]; then
        log_info "[DRYRUN] Would download $url -> $dest and chmod +x"
        return 0
    fi

    mkdir -p "$(dirname "$dest")" 2>/dev/null || true
    if command -v curl >/dev/null 2>&1; then
        run_cmd "curl -fsSL \"$url\" -o \"$dest\""
    elif command -v wget >/dev/null 2>&1; then
        run_cmd "wget -qO \"$dest\" \"$url\""
    else
        log_error "Neither curl nor wget is installed to download $url"
        runtime_install_instruction "curl"
        return 1
    fi

    chmod +x "$dest" 2>/dev/null || true
    return 0
}

# Internal helper: resolve a script path relative to CWD or caller script's $DIR
function _mbf_resolve_runtime_script() {
    local target="$1"
    if [ -f "$target" ]; then
        printf '%s\n' "$target"
        return 0
    elif [ -n "${DIR:-}" ] && [ -f "${DIR}/${target}" ]; then
        printf '%s\n' "${DIR}/${target}"
        return 0
    fi
    return 1
}

# ==============================================================================
# Node.js Integration
# ==============================================================================

# Check if Node.js is installed (and optionally meets minimum major version)
# Usage: runtime_check_node [min_major_version]
function runtime_check_node() {
    local min_major="${1:-}"
    local node_bin="${MBF_NODE_BIN:-node}"

    if ! command -v "$node_bin" >/dev/null 2>&1; then
        print_with_color "Node.js ('$node_bin') is not installed." "yellow"
        runtime_install_instruction "nodejs" "https://nodejs.org/"
        return 1
    fi

    if [ -n "$min_major" ]; then
        local ver_str major_ver
        ver_str="$("$node_bin" -v 2>/dev/null || echo "v0.0.0")"
        major_ver="${ver_str#v}"
        major_ver="${major_ver%%.*}"
        if [ "${major_ver:-0}" -lt "$min_major" ] 2>/dev/null; then
            print_with_color "Node.js version >= v${min_major} is required (found: ${ver_str})." "red"
            runtime_install_instruction "nodejs" "https://nodejs.org/"
            return 1
        fi
    fi
    return 0
}

# Install npm dependencies if package.json exists in target directory
# Usage: runtime_install_npm_deps [project_dir]
function runtime_install_npm_deps() {
    local proj_dir="${1:-${DIR:-.}}"
    local dryrun="${MBF_DRYRUN:-${I7R_DRYRUN:-0}}"

    if [ ! -f "${proj_dir}/package.json" ]; then
        log_warn "No package.json found in '${proj_dir}'"
        return 1
    fi

    if ! runtime_check_node; then
        return 1
    fi

    if [ "$dryrun" == "1" ]; then
        log_info "[DRYRUN] Would run: npm --prefix \"$proj_dir\" install"
        return 0
    fi

    run_cmd "npm --prefix \"$proj_dir\" install"
}

# Run a Node.js script interactively or with CLI arguments
# Usage: runtime_run_node <script.js> [args...]
function runtime_run_node() {
    local script_arg="$1"
    shift 1 2>/dev/null || true
    local node_bin="${MBF_NODE_BIN:-node}"
    local dryrun="${MBF_DRYRUN:-${I7R_DRYRUN:-0}}"

    if [ -z "$script_arg" ]; then
        log_error "runtime_run_node: script file path is required"
        return 1
    fi

    local resolved_script
    if ! resolved_script="$(_mbf_resolve_runtime_script "$script_arg")"; then
        log_error "Node.js script not found: $script_arg"
        return 1
    fi

    if [ "$dryrun" == "1" ]; then
        log_info "[DRYRUN] Would execute: $node_bin $resolved_script $*"
        return 0
    fi

    if ! runtime_check_node; then
        return 1
    fi

    "$node_bin" "$resolved_script" "$@"
}

# Evaluate inline Node.js code
# Usage: runtime_eval_node "console.log(process.argv[1])" "hello"
function runtime_eval_node() {
    local code="$1"
    shift 1 2>/dev/null || true
    local node_bin="${MBF_NODE_BIN:-node}"

    if ! runtime_check_node; then
        return 1
    fi

    "$node_bin" -e "$code" "$@"
}

# ==============================================================================
# Python Integration
# ==============================================================================

# Resolve Python binary (MBF_PYTHON_BIN, python3, or python)
function _mbf_find_python_bin() {
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

# Check if Python is installed (and optionally meets minimum major.minor version)
# Usage: runtime_check_python [min_version]
function runtime_check_python() {
    local min_ver="${1:-}"
    local py_bin

    if ! py_bin="$(_mbf_find_python_bin)"; then
        print_with_color "Python ('python3' or 'python') is not installed." "yellow"
        runtime_install_instruction "python3" "https://www.python.org/downloads/"
        return 1
    fi

    if [ -n "$min_ver" ]; then
        local found_ver
        found_ver="$("$py_bin" --version 2>&1 | awk '{print $2}')"
        local req_major="${min_ver%%.*}"
        local found_major="${found_ver%%.*}"
        if [ "${found_major:-0}" -lt "${req_major:-3}" ] 2>/dev/null; then
            print_with_color "Python version >= ${min_ver} is required (found: ${found_ver})." "red"
            runtime_install_instruction "python3" "https://www.python.org/downloads/"
            return 1
        fi
    fi
    return 0
}

# Install Python dependencies from requirements.txt (optionally inside a virtualenv)
# Usage: runtime_install_pip_deps [requirements_file] [venv_dir]
function runtime_install_pip_deps() {
    local req_file="${1:-${DIR:-.}/requirements.txt}"
    local venv_dir="${2:-}"
    local dryrun="${MBF_DRYRUN:-${I7R_DRYRUN:-0}}"

    if ! req_file="$(_mbf_resolve_runtime_script "$req_file")"; then
        log_warn "Python requirements file not found: $1"
        return 1
    fi

    local py_bin
    if ! py_bin="$(_mbf_find_python_bin)"; then
        runtime_check_python
        return 1
    fi

    if [ "$dryrun" == "1" ]; then
        log_info "[DRYRUN] Would install pip dependencies from $req_file"
        return 0
    fi

    if [ -n "$venv_dir" ]; then
        if [ ! -d "$venv_dir" ]; then
            run_cmd "\"$py_bin\" -m venv \"$venv_dir\""
        fi
        run_cmd "\"${venv_dir}/bin/pip\" install -r \"$req_file\""
    else
        run_cmd "\"$py_bin\" -m pip install -r \"$req_file\""
    fi
}

# Run a Python script interactively or with CLI arguments
# Usage: runtime_run_python <script.py> [args...]
function runtime_run_python() {
    local script_arg="$1"
    shift 1 2>/dev/null || true
    local dryrun="${MBF_DRYRUN:-${I7R_DRYRUN:-0}}"

    if [ -z "$script_arg" ]; then
        log_error "runtime_run_python: script file path is required"
        return 1
    fi

    local resolved_script
    if ! resolved_script="$(_mbf_resolve_runtime_script "$script_arg")"; then
        log_error "Python script not found: $script_arg"
        return 1
    fi

    if [ "$dryrun" == "1" ]; then
        log_info "[DRYRUN] Would execute: python3 $resolved_script $*"
        return 0
    fi

    local py_bin
    if ! py_bin="$(_mbf_find_python_bin)"; then
        runtime_check_python
        return 1
    fi

    "$py_bin" "$resolved_script" "$@"
}

# Evaluate inline Python code
# Usage: runtime_eval_python "import sys; print(sys.argv[1])" "hello"
function runtime_eval_python() {
    local code="$1"
    shift 1 2>/dev/null || true
    local py_bin

    if ! py_bin="$(_mbf_find_python_bin)"; then
        runtime_check_python
        return 1
    fi

    "$py_bin" -c "$code" "$@"
}
