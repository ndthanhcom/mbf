#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use ai exec

function test_ai_provider_priority_detection() {
    local work_dir
    mbf::exec::tmpdir work_dir

    cat <<'EOF' > "${work_dir}/claude"
#!/usr/bin/env bash
echo "CLAUDE_RESPONSE:$*"
EOF
    cat <<'EOF' > "${work_dir}/agy"
#!/usr/bin/env bash
echo "AGY_RESPONSE:$*"
EOF
    cat <<'EOF' > "${work_dir}/codex"
#!/usr/bin/env bash
echo "CODEX_RESPONSE:$*"
EOF
    chmod +x "${work_dir}/claude" "${work_dir}/agy" "${work_dir}/codex"

    local detected
    detected="$(PATH="${work_dir}:$PATH" mbf::ai::detect)"
    assert_eq "claude" "$detected"

    detected="$(PATH="${work_dir}:$PATH" MBF_AI_PROVIDER="agy" mbf::ai::detect)"
    assert_eq "agy" "$detected"

    detected="$(PATH="${work_dir}:$PATH" MBF_AI_PROVIDER="codex" mbf::ai::detect)"
    assert_eq "codex" "$detected"
}

function test_ai_analyze_file_piped_stdin_and_http_api_fallback() {
    local work_dir err_log
    mbf::exec::tmpdir work_dir
    err_log="${work_dir}/nginx-error.log"

    cat <<'EOF' > "$err_log"
2026/11/14 01:15:02 [error] 1042#1042: *99 connect() to unix:/run/php/php8.2-fpm.sock failed (11: Resource temporarily unavailable)
EOF

    cat <<'EOF' > "${work_dir}/claude"
#!/usr/bin/env bash
shift # -p
if [[ "$1" == *"Output ONLY the exact bash command"* ]]; then
    printf '```bash\nfind /var/log/nginx -name "*.log" -size +100M -delete\n```\n'
else
    printf 'DIAGNOSIS: Increase pm.max_children\nINPUT:%s\n' "$1"
fi
EOF
    chmod +x "${work_dir}/claude"

    # 1. File context analysis
    local analysis_out stdin_out cmd_out
    analysis_out="$(PATH="${work_dir}:$PATH" MBF_AI_PROVIDER="claude" mbf::ai::analyze "$err_log" "Diagnose 502 Bad Gateway")"
    assert_contains "$analysis_out" "DIAGNOSIS: Increase pm.max_children"
    assert_contains "$analysis_out" "php8.2-fpm.sock failed"

    # 2. Piped stdin (`-`) analysis
    stdin_out="$(printf 'Fatal error: Allowed memory size of 134217728 bytes exhausted\n' | PATH="${work_dir}:$PATH" MBF_AI_PROVIDER="claude" mbf::ai::analyze - "Fix PHP OOM")"
    assert_contains "$stdin_out" "Allowed memory size of 134217728 bytes exhausted"

    # 3. Command generation with fence stripping
    cmd_out="$(PATH="${work_dir}:$PATH" MBF_AI_PROVIDER="claude" mbf::ai::cmd "delete nginx logs larger than 100MB")"
    assert_eq 'find /var/log/nginx -name "*.log" -size +100M -delete' "$cmd_out"

    # 4. Zero-CLI HTTP API fallback using mock curl
    cat <<'EOF' > "${work_dir}/curl"
#!/usr/bin/env bash
printf '{"choices":[{"message":{"content":"API_FALLBACK_DIAGNOSIS_OK"}}]}\n'
EOF
    chmod +x "${work_dir}/curl"

    local api_out
    api_out="$(PATH="${work_dir}:$PATH" MBF_AI_PROVIDER="api" OPENAI_API_KEY="sk-test-key" mbf::ai::ask "Check Redis latency")"
    assert_eq "API_FALLBACK_DIAGNOSIS_OK" "$api_out"
}

run_test_suite "Plugin: AI CLI Integration (mbf::ai::*)"
