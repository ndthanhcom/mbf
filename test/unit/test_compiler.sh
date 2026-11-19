#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use exec system
source "${MBF_HOME}/tools/compiler.sh"

function test_compiler_does_not_silently_obfuscate_without_flag() {
    local work_dir src_script out_bin
    mbf::exec::tmpdir work_dir
    src_script="${work_dir}/hello.sh"
    out_bin="${work_dir}/hello_bin"

    cat <<'EOF' > "$src_script"
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::use log
mbf::log::info "hello"
EOF

    # Even when bash-obfuscate is installed in PATH, compiler must NOT invoke it unless --obfuscate is set
    mock_cmd "bash-obfuscate" 0
    cat <<EOF > "${MBF_MOCK_BIN}/shc"
#!/usr/bin/env bash
printf 'shc %s\n' "\$*" >> "${MBF_MOCK_LOG}"
out=""
while [ \$# -gt 0 ]; do
    if [ "\$1" == "-o" ]; then out="\$2"; shift 2; else shift 1; fi
done
[ -n "\$out" ] && printf 'FAKE_ELF\n' > "\$out"
exit 0
EOF
    chmod +x "${MBF_MOCK_BIN}/shc"

    (
        cd "$work_dir" || exit 1
        mbf::compiler::run "$src_script" -o "$out_bin" >/dev/null
    )
    assert_file_exists "$out_bin"
    assert_called_with "shc" "-f m_hello.sh"
    assert_not_called_with "bash-obfuscate"
}

function test_compiler_obfuscate_flag_and_missing_shc() {
    local work_dir src_script out_bin
    mbf::exec::tmpdir work_dir
    src_script="${work_dir}/secret.sh"
    out_bin="${work_dir}/secret_bin"

    cat <<'EOF' > "$src_script"
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::use log
mbf::log::info "secret"
EOF

    cat <<EOF > "${MBF_MOCK_BIN}/bash-obfuscate"
#!/usr/bin/env bash
printf 'bash-obfuscate %s\n' "\$*" >> "${MBF_MOCK_LOG}"
out=""
while [ \$# -gt 0 ]; do
    if [ "\$1" == "-o" ]; then out="\$2"; shift 2; else shift 1; fi
done
[ -n "\$out" ] && printf 'echo obfuscated\n' > "\$out"
exit 0
EOF
    cat <<EOF > "${MBF_MOCK_BIN}/shc"
#!/usr/bin/env bash
printf 'shc %s\n' "\$*" >> "${MBF_MOCK_LOG}"
out=""
while [ \$# -gt 0 ]; do
    if [ "\$1" == "-o" ]; then out="\$2"; shift 2; else shift 1; fi
done
[ -n "\$out" ] && printf 'FAKE_ELF\n' > "\$out"
exit 0
EOF
    chmod +x "${MBF_MOCK_BIN}/bash-obfuscate" "${MBF_MOCK_BIN}/shc"

    (
        cd "$work_dir" || exit 1
        mbf::compiler::run "$src_script" --obfuscate -o "$out_bin" >/dev/null
    )
    assert_file_exists "$out_bin"
    assert_called_with "bash-obfuscate" "m_secret.sh"
    assert_called_with "shc" "-f o_m_secret.sh"

    # Missing input script returns 1
    local rc=0
    mbf::compiler::run "${work_dir}/nonexistent.sh" >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc"
}

run_test_suite "Compiler Tool (tools/compiler.sh)"
