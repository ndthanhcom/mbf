#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf_use runtime

WORK_DIR=""

function setup() {
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mbf.runtime.XXXXXX")"
}

function teardown() {
    rm -rf "$WORK_DIR"
}

function test_system_pkg_detection_and_instructions() {
    local instr
    instr="$(runtime_install_instruction "jq" "https://jqlang.github.io/jq/")"
    assert_contains "$instr" 'Installation Instructions for "jq"'
    assert_contains "$instr" "https://jqlang.github.io/jq/"

    # Existing command should return 0
    runtime_ensure_pkg "bash" "bash"
    assert_eq "0" "$?"

    # Missing command should print instructions and return 1 when MBF_AUTO_INSTALL=0
    local missing_out
    missing_out="$(runtime_ensure_pkg "nonexistent_pkg_xyz" "nonexistent_cmd_xyz" "https://example.com/xyz")"
    assert_eq "1" "$?"
    assert_contains "$missing_out" "nonexistent_cmd_xyz"
    assert_contains "$missing_out" "https://example.com/xyz"

    # Dry-run download app
    MBF_DRYRUN="1"
    local dl_out
    dl_out="$(runtime_download_app "https://example.com/tool" "${WORK_DIR}/tool")"
    assert_eq "0" "$?"
    assert_contains "$dl_out" "Would download https://example.com/tool"
    MBF_DRYRUN="0"
}

function test_nodejs_runtime_execution_and_interactive_io() {
    local mock_node="${WORK_DIR}/mock_node"
    cat <<'EOF' > "$mock_node"
#!/usr/bin/env bash
if [ "$1" == "-v" ]; then
    echo "v18.19.0"
    exit 0
fi
if [ "$1" == "-e" ]; then
    echo "EVAL_JS:$2:$3"
    exit 0
fi
# Simulate interactive stdin + argument handling
read -r user_input
echo "NODE_SCRIPT=$(basename "$1")|ARG=$2|STDIN=$user_input"
EOF
    chmod +x "$mock_node"

    local js_script="${WORK_DIR}/app.js"
    printf '// sample node script\n' > "$js_script"

    export PATH="${WORK_DIR}:$PATH"
    export MBF_NODE_BIN="mock_node"

    runtime_check_node 18
    assert_eq "0" "$?"

    runtime_check_node 22 >/dev/null 2>&1
    assert_eq "1" "$?" "Should fail when required Node major version is higher than installed"

    local run_out
    run_out="$(printf 'interactive_hello\n' | runtime_run_node "$js_script" "--port=3000")"
    assert_eq "0" "$?"
    assert_contains "$run_out" "NODE_SCRIPT=app.js|ARG=--port=3000|STDIN=interactive_hello"

    local eval_out
    eval_out="$(runtime_eval_node "console.log(1)" "arg1")"
    assert_contains "$eval_out" "EVAL_JS:console.log(1):arg1"

    unset MBF_NODE_BIN
}

function test_python_runtime_execution_and_interactive_io() {
    local mock_py="${WORK_DIR}/mock_python3"
    cat <<'EOF' > "$mock_py"
#!/usr/bin/env bash
if [ "$1" == "--version" ]; then
    echo "Python 3.10.12"
    exit 0
fi
if [ "$1" == "-c" ]; then
    echo "EVAL_PY:$2:$3"
    exit 0
fi
read -r py_stdin
echo "PY_SCRIPT=$(basename "$1")|ARG=$2|STDIN=$py_stdin"
EOF
    chmod +x "$mock_py"

    local py_script="${WORK_DIR}/script.py"
    printf '# sample python script\n' > "$py_script"

    export PATH="${WORK_DIR}:$PATH"
    export MBF_PYTHON_BIN="mock_python3"

    runtime_check_python 3
    assert_eq "0" "$?"

    local run_out
    run_out="$(printf 'py_input_data\n' | runtime_run_python "$py_script" "--workers=4")"
    assert_eq "0" "$?"
    assert_contains "$run_out" "PY_SCRIPT=script.py|ARG=--workers=4|STDIN=py_input_data"

    local eval_out
    eval_out="$(runtime_eval_python "print('hi')" "extra")"
    assert_contains "$eval_out" "EVAL_PY:print('hi'):extra"

    # Dry-run pip install
    local req_file="${WORK_DIR}/requirements.txt"
    printf 'flask==3.0.0\n' > "$req_file"
    MBF_DRYRUN="1"
    local pip_out
    pip_out="$(runtime_install_pip_deps "$req_file")"
    assert_eq "0" "$?"
    assert_contains "$pip_out" "Would install pip dependencies"
    MBF_DRYRUN="0"

    unset MBF_PYTHON_BIN
}

run_test_suite "System, Node.js & Python Runtime Integration"
