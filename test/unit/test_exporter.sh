#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf_use exporter

WORK_DIR=""

function setup() {
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mbf.export.XXXXXX")"
}

function teardown() {
    rm -rf "$WORK_DIR"
}

function test_tree_shaking_and_standalone_execution() {
    local sample_script="${WORK_DIR}/sample_app.sh"
    local local_helper="${WORK_DIR}/local_helper.sh"
    local exported_script="${WORK_DIR}/standalone_app.sh"
    local target_conf="${WORK_DIR}/app.conf"

    cat <<'EOF' > "$local_helper"
function custom_local_banner() {
    echo "BANNER_OK"
}
EOF

    cat <<'EOF' > "$sample_script"
#!/usr/bin/env bash
DIR="${BASH_SOURCE%/*}"
source "$(mbf --init)"
mbf_use config
source "$DIR/local_helper.sh"

CONF_FILE="$1"
touch "$CONF_FILE"
custom_local_banner
insert_config "$CONF_FILE" "host = 127.0.0.1" >/dev/null
modify_config_value "$CONF_FILE" "host" "10.0.0.5" >/dev/null
echo "HOST_VAL=$(get_config_value "$CONF_FILE" "host")"
EOF

    mbf_export_script "$sample_script" -o "$exported_script"
    assert_file_exists "$exported_script"

    local exported_content
    exported_content="$(cat "$exported_script")"

    # 1. Verify used functions, local inlined script, and transitive dependencies ARE included
    assert_contains "$exported_content" "function custom_local_banner()"
    assert_contains "$exported_content" "function insert_config()"
    assert_contains "$exported_content" "function modify_config_value()"
    assert_contains "$exported_content" "function get_config_value()"
    assert_contains "$exported_content" "function _mbf_escape_sed_pattern()"
    assert_contains "$exported_content" "function run_cmd()"
    assert_contains "$exported_content" "function print_with_color()"

    # 2. Verify unused bloatware functions are NOT included
    assert_not_contains "$exported_content" "function yq_append_array_item()"
    assert_not_contains "$exported_content" "function run_continously()"
    assert_not_contains "$exported_content" "function run_parts_by_dir()"
    assert_not_contains "$exported_content" "mbf_use config"

    # 3. Execute exported standalone script with empty MBF_HOME to prove independence
    local output
    output="$(MBF_HOME="/nonexistent" bash "$exported_script" "$target_conf")"
    assert_contains "$output" "BANNER_OK"
    assert_contains "$output" "HOST_VAL=10.0.0.5"
}

function test_bundle_export_with_node_python_and_instructions() {
    local src_dir="${WORK_DIR}/src_project"
    local bundle_dir="${WORK_DIR}/dist_bundle"
    mkdir -p "$src_dir"

    cat <<'EOF' > "${src_dir}/worker.js"
console.log("NODE_WORKER_OK:" + (process.argv[2] || ""));
EOF
    cat <<'EOF' > "${src_dir}/package.json"
{"name": "sample-worker", "version": "1.0.0"}
EOF
    cat <<'EOF' > "${src_dir}/analyzer.py"
import sys
print("PY_ANALYZER_OK:" + (sys.argv[1] if len(sys.argv) > 1 else ""))
EOF
    cat <<'EOF' > "${src_dir}/requirements.txt"
requests>=2.0.0
EOF

    cat <<'EOF' > "${src_dir}/polyglot_app.sh"
#!/usr/bin/env bash
source "$(mbf --init)"
mbf_use runtime

runtime_ensure_pkg "curl" "curl"
runtime_run_node "worker.js" "arg_js"
runtime_run_python "analyzer.py" "arg_py"
EOF

    mbf_export_script "${src_dir}/polyglot_app.sh" --bundle-dir "$bundle_dir"

    # Verify bundle directory structure and files
    assert_file_exists "${bundle_dir}/polyglot_app.sh"
    assert_file_exists "${bundle_dir}/worker.js"
    assert_file_exists "${bundle_dir}/package.json"
    assert_file_exists "${bundle_dir}/analyzer.py"
    assert_file_exists "${bundle_dir}/requirements.txt"
    assert_file_exists "${bundle_dir}/INSTALL.md"

    local install_doc
    install_doc="$(cat "${bundle_dir}/INSTALL.md")"
    assert_contains "$install_doc" "polyglot_app.sh"
    assert_contains "$install_doc" "worker.js"
    assert_contains "$install_doc" "analyzer.py"
    assert_contains "$install_doc" "sudo apt-get update && sudo apt-get install -y curl"
    assert_contains "$install_doc" "npm install"
    assert_contains "$install_doc" "python3 -m pip install -r requirements.txt"

    # Verify exported bundle script executes with mock node/python runtimes from bundle_dir
    local mock_bin="${WORK_DIR}/mock_bin"
    mkdir -p "$mock_bin"
    cat <<'EOF' > "${mock_bin}/mock_node"
#!/usr/bin/env bash
if [ "$1" == "-v" ]; then echo "v20.10.0"; exit 0; fi
echo "EXECUTED_NODE:$(basename "$1"):$2"
EOF
    cat <<'EOF' > "${mock_bin}/mock_python"
#!/usr/bin/env bash
if [ "$1" == "--version" ]; then echo "Python 3.11.0"; exit 0; fi
echo "EXECUTED_PYTHON:$(basename "$1"):$2"
EOF
    chmod +x "${mock_bin}/mock_node" "${mock_bin}/mock_python"

    local bundle_run_out
    bundle_run_out="$(PATH="${mock_bin}:$PATH" MBF_NODE_BIN="mock_node" MBF_PYTHON_BIN="mock_python" MBF_HOME="/nonexistent" bash "${bundle_dir}/polyglot_app.sh")"
    assert_contains "$bundle_run_out" "EXECUTED_NODE:worker.js:arg_js"
    assert_contains "$bundle_run_out" "EXECUTED_PYTHON:analyzer.py:arg_py"
}

run_test_suite "Smart Exporter & Bundle Packaging"
