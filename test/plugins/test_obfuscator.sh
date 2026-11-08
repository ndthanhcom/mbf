#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use obfuscator fs

function test_obfuscator_plugin_dryrun_and_mock() {
    local work_dir sample_sh out_sh
    mbf::fs::tmpdir work_dir
    sample_sh="${work_dir}/sample.sh"
    out_sh="${work_dir}/obf_sample.sh"
    printf '#!/usr/bin/env bash\necho "secret"\n' > "$sample_sh"

    MBF_DRYRUN="1"
    local dry_out
    dry_out="$(mbf::obfuscator::run "$sample_sh" "$out_sh")"
    assert_eq "0" "$?"
    assert_contains "$dry_out" "Would obfuscate"
    MBF_DRYRUN="0"

    # Test with mock bash-obfuscate binary
    cat <<'EOF' > "${work_dir}/bash-obfuscate"
#!/usr/bin/env bash
# usage: bash-obfuscate <in> -o <out>
printf '# obfuscated\n%s\n' "$(cat "$1")" > "$3"
EOF
    chmod +x "${work_dir}/bash-obfuscate"

    PATH="${work_dir}:$PATH" mbf::obfuscator::run "$sample_sh" "$out_sh"
    assert_eq "0" "$?"
    assert_file_exists "$out_sh"
    assert_contains "$(cat "$out_sh")" "# obfuscated"
}

run_test_suite "Plugin: Obfuscator (mbf::obfuscator::*)"
