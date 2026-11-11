#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use runtime exec

function test_system_pkg_detection_and_instructions() {
    local work_dir instr missing_out dl_out
    mbf::exec::tmpdir work_dir

    instr="$(mbf::runtime::install_hint "jq" "https://jqlang.github.io/jq/")"
    assert_contains "$instr" 'Installation Instructions for "jq"'
    assert_contains "$instr" "https://jqlang.github.io/jq/"

    mbf::runtime::ensure_pkg "bash" "bash"
    assert_eq "0" "$?"

    missing_out="$(mbf::runtime::ensure_pkg "nonexistent_pkg_xyz" "nonexistent_cmd_xyz" "https://example.com/xyz" 2>&1)"
    assert_eq "1" "$?"
    assert_contains "$missing_out" "nonexistent_cmd_xyz"
    assert_contains "$missing_out" "https://example.com/xyz"

    MBF_DRYRUN="1"
    dl_out="$(mbf::runtime::download "https://deployer.org/deployer.phar" "${work_dir}/dep")"
    assert_eq "0" "$?"
    assert_contains "$dl_out" "Would download https://deployer.org/deployer.phar"
}

function test_nodejs_runtime_execution_and_interactive_io() {
    local work_dir mock_node js_script run_out
    mbf::exec::tmpdir work_dir
    mock_node="${work_dir}/mock_node"

    cat <<'EOF' > "$mock_node"
#!/usr/bin/env bash
if [ "$1" == "-v" ]; then echo "v20.11.0"; exit 0; fi
read -r user_input
echo "NODE_SCRIPT=$(basename "$1")|ARG=$2|STDIN=$user_input"
EOF
    chmod +x "$mock_node"

    js_script="${work_dir}/sitemap-parser.js"
    printf '// sitemap parser\n' > "$js_script"

    export PATH="${work_dir}:$PATH"
    export MBF_NODE_BIN="mock_node"

    mbf::runtime::check_node 18
    assert_eq "0" "$?"

    mbf::runtime::check_node 22 >/dev/null 2>&1
    assert_eq "1" "$?"

    run_out="$(printf 'https://shop.example.com/sitemap.xml\n' | mbf::runtime::run_node "$js_script" "--concurrency=8")"
    assert_eq "0" "$?"
    assert_contains "$run_out" "NODE_SCRIPT=sitemap-parser.js|ARG=--concurrency=8|STDIN=https://shop.example.com/sitemap.xml"
}

function test_python_runtime_execution_and_interactive_io() {
    local work_dir mock_py py_script req_file run_out pip_out
    mbf::exec::tmpdir work_dir
    mock_py="${work_dir}/mock_python3"

    cat <<'EOF' > "$mock_py"
#!/usr/bin/env bash
if [ "$1" == "--version" ]; then echo "Python 3.11.6"; exit 0; fi
read -r py_stdin
echo "PY_SCRIPT=$(basename "$1")|ARG=$2|STDIN=$py_stdin"
EOF
    chmod +x "$mock_py"

    py_script="${work_dir}/log_anomaly_detector.py"
    printf '# python log analyzer\n' > "$py_script"

    export PATH="${work_dir}:$PATH"
    export MBF_PYTHON_BIN="mock_python3"

    mbf::runtime::check_python 3
    assert_eq "0" "$?"

    run_out="$(printf '502_bad_gateway_line\n' | mbf::runtime::run_python "$py_script" "--threshold=5")"
    assert_eq "0" "$?"
    assert_contains "$run_out" "PY_SCRIPT=log_anomaly_detector.py|ARG=--threshold=5|STDIN=502_bad_gateway_line"

    req_file="${work_dir}/requirements.txt"
    printf 'httpx==0.27.0\n' > "$req_file"
    MBF_DRYRUN="1"
    pip_out="$(mbf::runtime::pip_install "$req_file")"
    assert_eq "0" "$?"
    assert_contains "$pip_out" "pip install -r"
}

run_test_suite "Plugin: Runtime (mbf::runtime::*)"
