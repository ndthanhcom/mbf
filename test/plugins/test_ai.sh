#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use ai exec

function test_ai_provider_priority_detection() {
    local work_dir
    mbf::exec::tmpdir work_dir

    # Create mock mainstream AI CLI binaries (claude, agy, codex)
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

    # When claude, agy, and codex are in PATH, claude is #1 priority
    local detected
    detected="$(PATH="${work_dir}:$PATH" mbf::ai::detect)"
    assert_eq "claude" "$detected"

    # Explicit MBF_AI_PROVIDER override selects agy or codex
    detected="$(PATH="${work_dir}:$PATH" MBF_AI_PROVIDER="agy" mbf::ai::detect)"
    assert_eq "agy" "$detected"

    detected="$(PATH="${work_dir}:$PATH" MBF_AI_PROVIDER="codex" mbf::ai::detect)"
    assert_eq "codex" "$detected"
}

function test_ai_analyze_nginx_error_log_and_generate_cmd() {
    local work_dir err_log
    mbf::exec::tmpdir work_dir
    err_log="${work_dir}/nginx-error.log"

    cat <<'EOF' > "$err_log"
2026/11/12 01:15:02 [error] 1042#1042: *99 connect() to unix:/run/php/php8.2-fpm.sock failed (11: Resource temporarily unavailable) while connecting to upstream
EOF

    cat <<'EOF' > "${work_dir}/claude"
#!/usr/bin/env bash
# Mock claude CLI (-p <prompt>)
shift # -p
if [[ "$1" == *"Output ONLY the exact bash command"* ]]; then
    printf '```bash\nfind /var/log/nginx -name "*.log" -size +100M -delete\n```\n'
else
    printf 'DIAGNOSIS: Increase pm.max_children in /etc/php/8.2/fpm/pool.d/www.conf\nINPUT:%s\n' "$1"
fi
EOF
    chmod +x "${work_dir}/claude"

    local analysis_out cmd_out
    analysis_out="$(PATH="${work_dir}:$PATH" MBF_AI_PROVIDER="claude" mbf::ai::analyze "$err_log" "Diagnose 502 Bad Gateway")"
    assert_contains "$analysis_out" "DIAGNOSIS: Increase pm.max_children"
    assert_contains "$analysis_out" "php8.2-fpm.sock failed"

    cmd_out="$(PATH="${work_dir}:$PATH" MBF_AI_PROVIDER="claude" mbf::ai::cmd "delete nginx logs larger than 100MB")"
    assert_eq 'find /var/log/nginx -name "*.log" -size +100M -delete' "$cmd_out"

    # Verify dry-run safety
    MBF_DRYRUN="1"
    local dry_out
    dry_out="$(MBF_AI_PROVIDER="agy" mbf::ai::ask "Review Magento 2 Varnish VCL")"
    assert_contains "$dry_out" "Would query AI provider 'agy'"
}

run_test_suite "Plugin: AI CLI Integration (mbf::ai::*)"
