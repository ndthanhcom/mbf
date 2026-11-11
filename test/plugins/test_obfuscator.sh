#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use obfuscator exec

function test_obfuscator_plugin_dryrun_and_mock() {
    local work_dir sample_sh out_sh
    mbf::exec::tmpdir work_dir
    sample_sh="${work_dir}/provision.sh"
    out_sh="${work_dir}/obf_provision.sh"
    printf '#!/usr/bin/env bash\necho "provisioning"\n' > "$sample_sh"

    MBF_DRYRUN="1"
    local dry_out
    dry_out="$(mbf::obfuscator::run "$sample_sh" "$out_sh")"
    assert_eq "0" "$?"
    assert_contains "$dry_out" "Would obfuscate"
    MBF_DRYRUN="0"

    cat <<'EOF' > "${work_dir}/bash-obfuscate"
#!/usr/bin/env bash
printf '# obfuscated\n%s\n' "$(cat "$1")" > "$3"
EOF
    chmod +x "${work_dir}/bash-obfuscate"

    PATH="${work_dir}:$PATH" mbf::obfuscator::run "$sample_sh" "$out_sh"
    assert_eq "0" "$?"
    assert_file_exists "$out_sh"
    assert_contains "$(cat "$out_sh")" "# obfuscated"
}

run_test_suite "Plugin: Obfuscator (mbf::obfuscator::*)"
