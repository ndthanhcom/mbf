#!/usr/bin/env bash
# ==============================================================================
# mbf (Micro Bash Framework) One-Command Installer
#
# Remote install (latest or pinned tag):
#   curl -fsSL https://raw.githubusercontent.com/ndthanhcom/mbf/master/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/ndthanhcom/mbf/v1.0.0/install.sh | bash -s -- --version v1.0.0
#
# Local install:
#   bash install.sh [--in-place] [--prefix ~/.mbf] [--rc-file ~/.bashrc] [--version v1.0.0]
# ==============================================================================

set -e

REPO_URL="${MBF_REPO_URL:-https://github.com/ndthanhcom/mbf.git}"
INSTALL_DIR="${MBF_INSTALL_DIR:-$HOME/.mbf}"
VERSION_REF="${MBF_VERSION_REF:-}"
IN_PLACE=0
CUSTOM_RC_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --in-place)
            IN_PLACE=1
            shift 1
            ;;
        --prefix)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --rc-file)
            CUSTOM_RC_FILE="$2"
            shift 2
            ;;
        --version)
            VERSION_REF="$2"
            shift 2
            ;;
        *)
            shift 1
            ;;
    esac
done

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_SOURCE" ] && [ -f "$(dirname "$SCRIPT_SOURCE")/framework.sh" ]; then
    LOCAL_SRC_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
else
    LOCAL_SRC_DIR=""
fi

if [ "$IN_PLACE" -eq 1 ] && [ -n "$LOCAL_SRC_DIR" ]; then
    INSTALL_DIR="$LOCAL_SRC_DIR"
elif [ -n "$LOCAL_SRC_DIR" ]; then
    if [ "$LOCAL_SRC_DIR" != "$INSTALL_DIR" ]; then
        mkdir -p "$INSTALL_DIR"
        cp -R "${LOCAL_SRC_DIR}/." "$INSTALL_DIR/"
    fi
else
    if [ -d "$INSTALL_DIR/.git" ]; then
        if [ -n "$VERSION_REF" ]; then
            echo "[mbf] Checking out pinned version '$VERSION_REF' in $INSTALL_DIR..."
            git -C "$INSTALL_DIR" fetch --tags origin
            git -C "$INSTALL_DIR" checkout "$VERSION_REF"
        else
            echo "[mbf] Updating existing installation in $INSTALL_DIR..."
            git -C "$INSTALL_DIR" pull --ff-only
        fi
    else
        if [ -n "$VERSION_REF" ]; then
            echo "[mbf] Cloning mbf ($VERSION_REF) into $INSTALL_DIR..."
            git clone --depth 1 --branch "$VERSION_REF" "$REPO_URL" "$INSTALL_DIR"
        else
            echo "[mbf] Cloning mbf into $INSTALL_DIR..."
            git clone "$REPO_URL" "$INSTALL_DIR"
        fi
    fi
fi

chmod +x "$INSTALL_DIR/bin/mbf" "$INSTALL_DIR/framework.sh" 2>/dev/null || true

# Append/replace idempotent initialization block (with shell completion) in target shell profile(s)
configure_rc_file() {
    local rc_file="$1"
    local marker_start="# >>> mbf initialize >>>"
    local marker_end="# <<< mbf initialize <<<"
    local comp_line='[ -n "${BASH_VERSION:-}" ] && command -v mbf >/dev/null 2>&1 && eval "$(mbf completion bash)"'

    case "$(basename "$rc_file")" in
        *zsh*)
            comp_line='[ -n "${ZSH_VERSION:-}" ] && command -v mbf >/dev/null 2>&1 && eval "$(mbf completion zsh)"'
            ;;
    esac

    if [ ! -f "$rc_file" ]; then
        touch "$rc_file"
    fi

    # Remove any previous MBF block (CRLF-safe) or legacy unmarked MBF lines before writing updated block
    local tmp_rc="${rc_file}.mbf.tmp.$$"
    awk -v start="$marker_start" -v end="$marker_end" '
        {
            line = $0
            sub(/\r$/, "", line)
            sub(/[[:space:]]+$/, "", line)
        }
        line == start { skip = 1; next }
        line == end   { skip = 0; next }
        skip          { next }
        line ~ /^export[[:space:]]+MBF_HOME=/ { next }
        line ~ /^export[[:space:]]+PATH="\$MBF_HOME\/bin:\$PATH"$/ { next }
        line ~ /mbf completion (bash|zsh)/ { next }
        { print }
    ' "$rc_file" > "$tmp_rc"
    mv "$tmp_rc" "$rc_file"

    cat <<EOF >> "$rc_file"
$marker_start
export MBF_HOME="$INSTALL_DIR"
export PATH="\$MBF_HOME/bin:\$PATH"
$comp_line
$marker_end
EOF
    echo "[mbf] Configured $rc_file"
}

if [ -n "$CUSTOM_RC_FILE" ]; then
    configure_rc_file "$CUSTOM_RC_FILE"
else
    configured_any=0
    if [ -f "$HOME/.bashrc" ]; then
        configure_rc_file "$HOME/.bashrc"
        configured_any=1
    fi
    if [ -f "$HOME/.bash_profile" ]; then
        configure_rc_file "$HOME/.bash_profile"
        configured_any=1
    fi
    if [ -f "$HOME/.zshrc" ]; then
        configure_rc_file "$HOME/.zshrc"
        configured_any=1
    fi
    if [ "$configured_any" -eq 0 ]; then
        configure_rc_file "$HOME/.bashrc"
    fi
fi

echo "[mbf] Installation complete! Run 'source ~/.bashrc' (or ~/.zshrc / ~/.bash_profile) or start a new shell."
