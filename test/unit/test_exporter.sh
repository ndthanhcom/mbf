#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use fs
source "${MBF_HOME}/tools/exporter.sh"

function test_single_pass_tree_shaking_and_state_export() {
    local work_dir
    mbf::fs::tmpdir work_dir
    local sample_script="${work_dir}/sample_app.sh"
    local local_helper="${work_dir}/local_helper.sh"
    local exported_script="${work_dir}/standalone_app.sh"
    local target_conf="${work_dir}/app.conf"

    cat <<'EOF' > "$local_helper"
function custom_local_banner() {
    echo "BANNER_OK"
}
EOF

    cat <<'EOF' > "$sample_script"
#!/usr/bin/env bash
set -u
DIR="${BASH_SOURCE%/*}"
source "$(mbf --init)"
mbf::use config args
source "$DIR/local_helper.sh"

mbf::args::option "h" "host" "NEW_HOST" "Host IP" "10.0.0.5"
mbf::args::parse "$@"

CONF_FILE="${MBF_POSITIONAL_ARGS[0]}"
touch "$CONF_FILE"
custom_local_banner
mbf::config::insert "$CONF_FILE" "host = 127.0.0.1"
mbf::config::set "$CONF_FILE" "host" "$NEW_HOST"
echo "HOST_VAL=$(mbf::config::get "$CONF_FILE" "host")"
EOF

    mbf::exporter::run "$sample_script" -o "$exported_script"
    assert_file_exists "$exported_script"

    local exported_content
    exported_content="$(cat "$exported_script")"

    # 1. Verify module state block (`MBF_ARG_DEFS=""`) and used functions + dependencies are included
    assert_contains "$exported_content" 'MBF_ARG_DEFS=""'
    assert_contains "$exported_content" "function custom_local_banner()"
    assert_contains "$exported_content" "function mbf::config::insert()"
    assert_contains "$exported_content" "function mbf::config::set()"
    assert_contains "$exported_content" "function mbf::config::get()"
    assert_contains "$exported_content" "function _mbf_sed_escape_pattern()"
    assert_contains "$exported_content" "function mbf::args::parse()"

    # 2. Verify unused functions are excluded (tree-shaken)
    assert_not_contains "$exported_content" "function mbf::config::delete_line()"
    assert_not_contains "$exported_content" "function mbf::config::append_after_line()"
    assert_not_contains "$exported_content" "mbf::use config"

    # 3. Execute exported standalone script under `set -u` with empty MBF_HOME
    local output
    output="$(MBF_HOME="/nonexistent" bash "$exported_script" --host 10.0.0.99 "$target_conf")"
    assert_contains "$output" "BANNER_OK"
    assert_contains "$output" "HOST_VAL=10.0.0.99"
}

function test_bundle_export_with_node_python_and_instructions() {
    local work_dir
    mbf::fs::tmpdir work_dir
    local src_dir="${work_dir}/src_project"
    local bundle_dir="${work_dir}/dist_bundle"
    mkdir -p "$src_dir"

    printf 'console.log("NODE_OK");\n' > "${src_dir}/worker.js"
    printf '{"name": "sample-worker"}\n' > "${src_dir}/package.json"
    printf 'print("PY_OK")\n' > "${src_dir}/analyzer.py"
    printf 'requests>=2.0.0\n' > "${src_dir}/requirements.txt"

    cat <<'EOF' > "${src_dir}/polyglot_app.sh"
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::use runtime

mbf::runtime::ensure_pkg "curl" "curl"
mbf::runtime::run_node "worker.js" "arg_js"
mbf::runtime::run_python "analyzer.py" "arg_py"
EOF

    mbf::exporter::run "${src_dir}/polyglot_app.sh" --bundle-dir "$bundle_dir"

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
    assert_contains "$install_doc" "npm install"
    assert_contains "$install_doc" "python3 -m pip install -r requirements.txt"

    local mock_bin="${work_dir}/mock_bin"
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

run_test_suite "Smart Exporter & Bundle Packaging (tools/exporter.sh)"
