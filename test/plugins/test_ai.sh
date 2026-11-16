#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use ai exec

function test_ai_provider_priority_and_ensure() {
    mock_cmd "claude" 0 "CLAUDE_OK"
    mock_cmd "agy" 0 "AGY_OK"
    mock_cmd "codex" 0 "CODEX_OK"

    assert_eq "claude" "$(mbf::ai::detect)"
    assert_eq "agy" "$(MBF_AI_PROVIDER="agy" mbf::ai::detect)"
    assert_eq "codex" "$(MBF_AI_PROVIDER="codex" mbf::ai::detect)"
    assert_eq "0" "$(mbf::ai::ensure "claude" && echo 0 || echo 1)"

    local miss_out miss_rc=0
    miss_out="$(mbf::ai::ensure "nonexistent_ai_cli_xyz" 2>&1)" || miss_rc=$?
    assert_eq "1" "$miss_rc"
    assert_contains "$miss_out" "AI CLI Installation Guide"
}

function test_ai_analyze_file_piped_stdin_and_http_api_fallback() {
    local work_dir err_log
    mbf::exec::tmpdir work_dir
    err_log="${work_dir}/nginx-error.log"

    cat <<'EOF' > "$err_log"
2026/11/14 01:15:02 [error] 1042#1042: *99 connect() to unix:/run/php/php8.2-fpm.sock failed (11: Resource temporarily unavailable)
EOF

    cat <<'EOF' > "${MBF_MOCK_BIN}/claude"
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "${MBF_MOCK_LOG}"
while [ $# -gt 1 ]; do shift; done
if [[ "$1" == *"Output ONLY the exact bash command"* ]]; then
    printf '```bash\nfind /var/log/nginx -name "*.log" -size +100M -delete\n```\n'
else
    printf 'DIAGNOSIS: Increase pm.max_children\nINPUT:%s\n' "$1"
fi
EOF
    chmod +x "${MBF_MOCK_BIN}/claude"

    # 1. File context analysis + custom model flag (R3)
    local analysis_out stdin_out cmd_out
    analysis_out="$(MBF_AI_PROVIDER="claude" MBF_AI_MODEL="claude-sonnet-4" mbf::ai::analyze "$err_log" "Diagnose 502 Bad Gateway")"
    assert_contains "$analysis_out" "DIAGNOSIS: Increase pm.max_children"
    assert_contains "$analysis_out" "php8.2-fpm.sock failed"
    assert_called_with "claude" "--model claude-sonnet-4 -p"

    # 2. Piped stdin (`-`) analysis
    stdin_out="$(printf 'Fatal error: Allowed memory size of 134217728 bytes exhausted\n' | MBF_AI_PROVIDER="claude" mbf::ai::analyze - "Fix PHP OOM")"
    assert_contains "$stdin_out" "Allowed memory size of 134217728 bytes exhausted"

    # 3. Command generation with fence stripping
    cmd_out="$(MBF_AI_PROVIDER="claude" mbf::ai::cmd "delete nginx logs larger than 100MB")"
    assert_eq 'find /var/log/nginx -name "*.log" -size +100M -delete' "$cmd_out"

    # 4. Zero-CLI HTTP API fallback using mock curl (verifies Gemini header B17)
    mock_cmd "curl" 0 '{"candidates":[{"content":{"parts":[{"text":"GEMINI_HEADER_AUTH_OK"}]}}]}'
    local api_out
    api_out="$(MBF_AI_PROVIDER="api" GEMINI_API_KEY="gm-secret-key" mbf::ai::ask "Check Redis latency")"
    assert_eq "GEMINI_HEADER_AUTH_OK" "$api_out"
    assert_called_with "curl" "x-goog-api-key: gm-secret-key"
    assert_not_contains "$(cat "$MBF_MOCK_LOG")" "?key="
}

run_test_suite "Plugin: AI CLI Integration (mbf::ai::*)"
