#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use ai exec

function test_ai_provider_priority_and_ensure() {
    mock_cmd "claude" 0 "CLAUDE_OK"
    mock_cmd "agy" 0 "AGY_OK"
    mock_cmd "codex" 0 "CODEX_OK"

    assert_eq "agy" "$(mbf::ai::detect)"
    assert_eq "claude" "$(MBF_AI_PROVIDER="claude" mbf::ai::detect)"
    assert_eq "codex" "$(MBF_AI_PROVIDER="codex" mbf::ai::detect)"
    assert_eq "0" "$(mbf::ai::ensure "agy" && echo 0 || echo 1)"

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

    # 5. OpenAI-compatible custom MBF_AI_BASE_URL + MBF_AI_SYSTEM
    mock_cmd "curl" 0 '{"choices":[{"message":{"content":"OPENROUTER_OK"}}]}'
    local compat_out
    compat_out="$(MBF_AI_PROVIDER="api" OPENAI_API_KEY="or-key" MBF_AI_BASE_URL="https://openrouter.ai/api/v1" MBF_AI_SYSTEM="Be concise" mbf::ai::ask "Ping")"
    assert_eq "OPENROUTER_OK" "$compat_out"
    assert_called_with "curl" "https://openrouter.ai/api/v1/chat/completions"
    assert_called_with "curl" "Be concise"
}

function test_ai_redaction_truncation_ask_json_and_safe_run() {
    local work_dir big_log
    mbf::exec::tmpdir work_dir
    big_log="${work_dir}/big.log"

    cat <<'EOF' > "${MBF_MOCK_BIN}/claude"
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "${MBF_MOCK_LOG}"
while [ $# -gt 1 ]; do shift; done
if [[ "$1" == *"Respond with ONLY valid raw JSON"* ]]; then
    if [[ "$1" == *"BAD_JSON"* ]]; then
        printf 'Sorry, not json\n'
    else
        printf '```json\n{"severity":"high","restart":true}\n```\n'
    fi
elif [[ "$1" == *"Output ONLY the exact bash command"* ]]; then
    printf 'echo SAFE_AI_RUN_OK\n'
else
    printf 'PROMPT_ECHO:%s\n' "$1"
fi
EOF
    chmod +x "${MBF_MOCK_BIN}/claude"

    # 1. Secret redaction before sending to LLM (MBF_LOG_REDACT + POSIX ERE Bearer/sk-/ghp_/AKIA/password patterns)
    mbf::log::redact "CUSTOM_SECRET_XYZ"
    local red_out
    red_out="$(MBF_AI_PROVIDER="claude" mbf::ai::ask "Check Authorization: Bearer eyJhbGciOiJIUzI1NiJ9 sk-proj1234567890abcdef ghp_1234567890abcdefghij AKIAIOSFODNN7EXAMPLE password=myPass123 CUSTOM_SECRET_XYZ")"
    assert_not_contains "$red_out" "eyJhbGciOiJIUzI1NiJ9"
    assert_not_contains "$red_out" "sk-proj1234567890abcdef"
    assert_not_contains "$red_out" "ghp_1234567890abcdefghij"
    assert_not_contains "$red_out" "AKIAIOSFODNN7EXAMPLE"
    assert_not_contains "$red_out" "myPass123"
    assert_not_contains "$red_out" "CUSTOM_SECRET_XYZ"
    assert_contains "$red_out" "***"

    # 2. Context size truncation keeps tail of large logs
    printf 'OLD_HEAD_DATA_MARKER\n' > "$big_log"
    printf 'MID_LOG_LINE_PADDING_%.0s' {1..10} >> "$big_log"
    printf '\nRECENT_TAIL_ERROR\n' >> "$big_log"
    local trunc_out
    trunc_out="$(MBF_AI_PROVIDER="claude" MBF_AI_MAX_CONTEXT_BYTES=40 mbf::ai::ask "Summarize" "$big_log" 2>/dev/null)"
    assert_contains "$trunc_out" "RECENT_TAIL_ERROR"
    assert_contains "$trunc_out" "truncated to last 40 bytes"
    assert_not_contains "$trunc_out" "OLD_HEAD_DATA_MARKER"

    # 3. Structured JSON mode (`ask_json`) strips fences and rejects non-JSON
    local json_out
    json_out="$(MBF_AI_PROVIDER="claude" mbf::ai::ask_json "Classify error")"
    assert_eq '{"severity":"high","restart":true}' "$json_out"
    assert_eq "high" "$(mbf::json::get "$json_out" "severity")"

    local bad_rc=0
    MBF_AI_PROVIDER="claude" mbf::ai::ask_json "BAD_JSON" >/dev/null 2>&1 || bad_rc=$?
    assert_eq "1" "$bad_rc" "ask_json must return 1 on non-JSON response"

    # 4. Safe human-in-the-loop `mbf::ai::run`: cancelled by default in CI, executes with MBF_YES=1
    local cancel_rc=0
    MBF_AI_PROVIDER="claude" CI=1 MBF_YES=0 mbf::ai::run "say ok" >/dev/null 2>&1 || cancel_rc=$?
    assert_eq "1" "$cancel_rc" "mbf::ai::run must NOT auto-execute without confirmation"

    local run_out
    run_out="$(MBF_AI_PROVIDER="claude" MBF_YES=1 mbf::ai::run "say ok" 2>/dev/null)"
    assert_contains "$run_out" "SAFE_AI_RUN_OK"
}

run_test_suite "Plugin: AI CLI Integration (mbf::ai::*)"
