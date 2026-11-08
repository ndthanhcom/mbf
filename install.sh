#!/usr/bin/env bash
# ==============================================================================
# mbf (Micro Bash Framework) One-Command Installer
#
# Remote install:
#   curl -fsSL https://raw.githubusercontent.com/ndthanhcom/mbf/master/install.sh | bash
#
# Local install:
#   bash install.sh [--in-place] [--prefix ~/.mbf] [--rc-file ~/.bashrc]
# ==============================================================================

set -e

REPO_URL="${MBF_REPO_URL:-https://github.com/ndthanhcom/mbf.git}"
INSTALL_DIR="${MBF_INSTALL_DIR:-$HOME/.mbf}"
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
        echo "[mbf] Updating existing installation in $INSTALL_DIR..."
        git -C "$INSTALL_DIR" pull --ff-only
    else
        echo "[mbf] Cloning mbf into $INSTALL_DIR..."
        git clone "$REPO_URL" "$INSTALL_DIR"
    fi
fi

chmod +x "$INSTALL_DIR/bin/mbf" "$INSTALL_DIR/framework.sh" 2>/dev/null || true

# Append idempotent initialization block to target shell profile(s)
configure_rc_file() {
    local rc_file="$1"
    local marker_start="# >>> mbf initialize >>>"
    local marker_end="# <<< mbf initialize <<<"

    if [ ! -f "$rc_file" ]; then
        touch "$rc_file"
    fi

    if grep -Fq "$marker_start" "$rc_file" 2>/dev/null; then
        # Remove old block before re-adding updated block
        local tmp_rc="${rc_file}.mbf.tmp"
        awk -v start="$marker_start" -v end="$marker_end" '
            $0 == start { skip = 1; next }
            $0 == end   { skip = 0; next }
            !skip       { print }
        ' "$rc_file" > "$tmp_rc"
        mv "$tmp_rc" "$rc_file"
    fi

    cat <<EOF >> "$rc_file"
$marker_start
export MBF_HOME="$INSTALL_DIR"
export PATH="\$MBF_HOME/bin:\$PATH"
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
    if [ "$configured_any" -eq 0 ]; then
        configure_rc_file "$HOME/.bashrc"
    fi
fi

echo "[mbf] Installation complete! Run 'source ~/.bashrc' (or ~/.bash_profile) or start a new shell."
