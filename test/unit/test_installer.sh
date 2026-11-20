#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use exec

function test_installer_rc_file_and_idempotency() {
    local mock_dir
    mbf::exec::tmpdir mock_dir
    local mock_rc="${mock_dir}/.bashrc"
    # Pre-populate with CRLF old MBF block + legacy unmarked line to verify full replacement
    printf '# Existing user bashrc\nexport EDITOR=vim\nexport MBF_HOME="/old/legacy/mbf"\n# >>> mbf initialize >>>\r\nexport MBF_HOME="/stale/mbf"\r\nexport PATH="$MBF_HOME/bin:$PATH"\r\n# <<< mbf initialize <<<\r\n' > "$mock_rc"

    bash "${MBF_HOME}/install.sh" --in-place --rc-file "$mock_rc" >/dev/null
    local first_rc
    first_rc="$(cat "$mock_rc")"
    bash "${MBF_HOME}/install.sh" --in-place --rc-file "$mock_rc" >/dev/null

    assert_eq "$first_rc" "$(cat "$mock_rc")" "Re-running install.sh must produce byte-identical rc file"
    assert_contains "$first_rc" "export EDITOR=vim"
    assert_contains "$first_rc" "export MBF_HOME="
    assert_contains "$first_rc" "export PATH=\"\$MBF_HOME/bin:\$PATH\""
    assert_contains "$first_rc" 'eval "$(mbf completion bash)"'
    assert_not_contains "$first_rc" "/old/legacy/mbf"
    assert_not_contains "$first_rc" "/stale/mbf"
    assert_eq "1" "$(grep -c "# >>> mbf initialize >>>" "$mock_rc")"

    # Verify zsh rc file gets zsh completion
    local mock_zshrc="${mock_dir}/.zshrc"
    printf '# User zshrc\n' > "$mock_zshrc"
    bash "${MBF_HOME}/install.sh" --in-place --rc-file "$mock_zshrc" >/dev/null
    assert_contains "$(cat "$mock_zshrc")" 'eval "$(mbf completion zsh)"'
}

function test_mbf_cli_list_ranks_new_ext_doctor_and_unknown_cmd() {
    local mock_dir
    mbf::exec::tmpdir mock_dir

    local init_path ver_out
    init_path="$(bash "${MBF_HOME}/bin/mbf" --init)"
    assert_eq "${MBF_HOME}/framework.sh" "$init_path"
    ver_out="$(bash "${MBF_HOME}/bin/mbf" --version)"
    assert_eq "mbf v1.0.0" "$ver_out"

    local list_out
    list_out="$(bash "${MBF_HOME}/bin/mbf" list)"
    assert_contains "$list_out" "Core Libraries"
    assert_contains "$list_out" "Plugins"
    assert_contains "$list_out" "mbf::ai::ask"
    assert_contains "$list_out" "mbf::backup::archive_dir"
    assert_contains "$list_out" "mbf::config::set"

    # Generate new script and new custom extension via `mbf new`
    local new_script="${mock_dir}/deploy.sh"
    local new_ext="${mock_dir}/jenkins.sh"
    bash "${MBF_HOME}/bin/mbf" new "$new_script" >/dev/null
    bash "${MBF_HOME}/bin/mbf" new --ext "$new_ext" >/dev/null

    assert_file_exists "$new_script"
    assert_file_exists "$new_ext"
    assert_contains "$(cat "$new_ext")" "# @mbf-module: jenkins"
    assert_contains "$(cat "$new_ext")" "function mbf::jenkins::run()"

    # Validate generated extension with `mbf doctor`
    bash "${MBF_HOME}/bin/mbf" doctor "$new_ext" >/dev/null

    # Unknown CLI command must exit with status 1
    local unk_rc=0
    bash "${MBF_HOME}/bin/mbf" unknown_subcommand >/dev/null 2>&1 || unk_rc=$?
    assert_eq "1" "$unk_rc"
}

function test_public_api_contract_matches_documentation() {
    # Every public `mbf::*` function in framework.sh, lib/*.sh, and plugins/*.sh
    # must be documented in docs/LIBRARIES.md or docs/PLUGINS.md AND in its
    # dedicated per-module guide in docs/libraries/<mod>.md or docs/plugins/<mod>.md.
    local f fn mod_name guide_file missing="" missing_guide=""
    for f in "${MBF_HOME}/framework.sh" "${MBF_HOME}"/lib/*.sh "${MBF_HOME}"/plugins/*.sh; do
        mod_name="$(basename "$f" .sh)"
        if [[ "$f" == *"/plugins/"* ]]; then
            guide_file="${MBF_HOME}/docs/plugins/${mod_name}.md"
        else
            guide_file="${MBF_HOME}/docs/libraries/${mod_name}.md"
        fi
        assert_file_exists "$guide_file" "Missing detailed guide for module '${mod_name}': ${guide_file}"

        while IFS= read -r fn; do
            [ -z "$fn" ] && continue
            if ! grep -Fq "$fn" "${MBF_HOME}/docs/LIBRARIES.md" "${MBF_HOME}/docs/PLUGINS.md"; then
                missing="${missing} ${fn}"
            fi
            if ! grep -Fq "$fn" "$guide_file"; then
                missing_guide="${missing_guide} ${fn}(${mod_name}.md)"
            fi
        done < <(grep -oE '^function[[:space:]]+mbf::[a-zA-Z0-9_:]+' "$f" | awk '{print $2}')
    done
    assert_eq "" "${missing# }" "Undocumented public mbf::* functions in index:${missing}"
    assert_eq "" "${missing_guide# }" "Undocumented public mbf::* functions in per-module guides:${missing_guide}"
}

run_test_suite "Installer, CLI & Public API Contract (bin/mbf, docs/)"
