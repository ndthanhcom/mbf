#!/usr/bin/env bash
# @mbf-module: ai
# @mbf-rank: •••
# mbf:requires log exec json net
# ==============================================================================
# mbf plugin: ai
# Mainstream AI CLI Integration (`claude`, `agy`, `gemini`, `codex`)
# with secondary fallback for `hermes`, `ollama`, `llm`, and direct HTTP APIs.
#
# Environment Variables:
#   MBF_AI_PROVIDER : Override provider (`claude`, `agy`, `gemini`, `codex`, `hermes`, `ollama`, `llm`, `api`)
#   MBF_AI_MODEL    : Optional model override (e.g. `claude-sonnet-4-20250514`, `gemini-2.5-pro`, `llama3`)
#   MBF_AI_CMD      : Optional custom AI command hook receiving prompt as $1
# ==============================================================================

# Detect active AI CLI provider in priority order:
# 1. Mainstream CLIs: claude -> agy -> gemini -> codex
# 2. Secondary agents/models: hermes -> ollama -> llm
# 3. Direct HTTP API fallback: ANTHROPIC_API_KEY / GEMINI_API_KEY / OPENAI_API_KEY
function mbf::ai::detect() {
    if [ -n "${MBF_AI_CMD:-}" ]; then
        printf 'custom\n'
        return 0
    fi
    if [ -n "${MBF_AI_PROVIDER:-}" ]; then
        printf '%s\n' "$MBF_AI_PROVIDER"
        return 0
    fi

    local cli
    # Priority 1: Mainstream AI CLIs
    for cli in claude agy gemini codex; do
        if command -v "$cli" >/dev/null 2>&1; then
            printf '%s\n' "$cli"
            return 0
        fi
    done

    # Priority 2: Secondary CLI agents & local models
    for cli in hermes ollama llm; do
        if command -v "$cli" >/dev/null 2>&1; then
            printf '%s\n' "$cli"
            return 0
        fi
    done

    # Priority 3: Direct HTTP API keys
    if [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${GEMINI_API_KEY:-}" ] || [ -n "${OPENAI_API_KEY:-}" ]; then
        printf 'api\n'
        return 0
    fi

    printf 'none\n'
    return 1
}

# Check if an AI CLI provider is available; print setup instructions if missing
# Usage: mbf::ai::ensure [preferred_provider]
function mbf::ai::ensure() {
    local pref="${1:-}"
    local detected

    if [ -n "$pref" ]; then
        if command -v "$pref" >/dev/null 2>&1; then
            return 0
        fi
    elif detected="$(mbf::ai::detect)"; then
        mbf::log::debug "Detected AI provider: $detected"
        return 0
    fi

    mbf::log::warn "No AI CLI tool detected (${pref:-claude, agy, gemini, codex})."
    cat <<'EOF'
=== AI CLI Installation Guide ===
  * Claude Code : npm install -g @anthropic-ai/claude-code
  * Antigravity : agy --version (install via Google Antigravity IDE / CLI)
  * Gemini CLI  : npm install -g @google/gemini-cli
  * OpenAI Codex: npm install -g @openai/codex
  * Or export ANTHROPIC_API_KEY / GEMINI_API_KEY / OPENAI_API_KEY for HTTP fallback.
EOF
    return 1
}

function _mbf_ai_api_call() {
    local prompt="$1"
    local esc_prompt payload resp
    esc_prompt="$(mbf::json::escape "$prompt")"

    if [ -n "${OPENAI_API_KEY:-}" ]; then
        local model="${MBF_AI_MODEL:-gpt-4o-mini}"
        payload="{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":\"${esc_prompt}\"}]}"
        resp="$(curl -fsSL https://api.openai.com/v1/chat/completions \
            -H "Authorization: Bearer ${OPENAI_API_KEY}" \
            -H "Content-Type: application/json" \
            --data "$payload")" || return 1
        mbf::json::get "$resp" "content"
    elif [ -n "${GEMINI_API_KEY:-}" ]; then
        local model="${MBF_AI_MODEL:-gemini-2.5-flash}"
        payload="{\"contents\":[{\"parts\":[{\"text\":\"${esc_prompt}\"}]}]}"
        resp="$(curl -fsSL "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}" \
            -H "Content-Type: application/json" \
            --data "$payload")" || return 1
        mbf::json::get "$resp" "text"
    elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        local model="${MBF_AI_MODEL:-claude-3-5-haiku-latest}"
        payload="{\"model\":\"${model}\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":\"${esc_prompt}\"}]}"
        resp="$(curl -fsSL https://api.anthropic.com/v1/messages \
            -H "x-api-key: ${ANTHROPIC_API_KEY}" \
            -H "anthropic-version: 2023-06-01" \
            -H "Content-Type: application/json" \
            --data "$payload")" || return 1
        mbf::json::get "$resp" "text"
    else
        mbf::log::error "mbf::ai: no API key set for HTTP fallback"
        return 1
    fi
}

# Send a non-interactive prompt (plus optional context file) to the active AI CLI
# Usage: mbf::ai::ask "<prompt>" [context_file]
function mbf::ai::ask() {
    local prompt="$1"
    local context_file="${2:-}"

    if [ -z "$prompt" ]; then
        mbf::log::error "mbf::ai::ask: prompt is required"
        return 1
    fi

    if [ -n "$context_file" ]; then
        if [ ! -f "$context_file" ]; then
            mbf::log::error "mbf::ai::ask: context file not found: $context_file"
            return 1
        fi
        prompt="${prompt}"$'\n\n--- Context ('"$(basename "$context_file")"') ---\n'"$(cat "$context_file")"
    fi

    local provider
    provider="$(mbf::ai::detect)" || {
        if mbf::is_dryrun; then
            provider="${MBF_AI_PROVIDER:-claude}"
        else
            mbf::ai::ensure
            return 1
        fi
    }

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would query AI provider '$provider': ${prompt%%$'\n'*}"
        return 0
    fi

    case "$provider" in
        custom)
            "$MBF_AI_CMD" "$prompt"
            ;;
        claude)
            if [ -n "${MBF_AI_MODEL:-}" ]; then
                claude --model "$MBF_AI_MODEL" -p "$prompt"
            else
                claude -p "$prompt"
            fi
            ;;
        agy)
            agy -p "$prompt"
            ;;
        gemini)
            if [ -n "${MBF_AI_MODEL:-}" ]; then
                gemini -m "$MBF_AI_MODEL" -p "$prompt"
            else
                gemini -p "$prompt"
            fi
            ;;
        codex)
            codex exec "$prompt"
            ;;
        hermes)
            if [ -n "${MBF_AI_MODEL:-}" ]; then
                hermes chat --model "$MBF_AI_MODEL" -q "$prompt"
            else
                hermes chat -q "$prompt"
            fi
            ;;
        ollama)
            ollama run "${MBF_AI_MODEL:-llama3}" "$prompt"
            ;;
        llm)
            if [ -n "${MBF_AI_MODEL:-}" ]; then
                llm -m "$MBF_AI_MODEL" "$prompt"
            else
                llm "$prompt"
            fi
            ;;
        api)
            _mbf_ai_api_call "$prompt"
            ;;
        *)
            mbf::log::error "Unsupported AI provider: $provider"
            return 1
            ;;
    esac
}

# Analyze a log file, config file, or command output string and return root-cause & fix steps
# Usage: mbf::ai::analyze <file_or_text> [custom_instruction]
function mbf::ai::analyze() {
    local target="$1"
    local instruction="${2:-Analyze the following output, identify root causes of any errors or risks, and provide concise remediation steps.}"

    if [ -f "$target" ]; then
        mbf::ai::ask "$instruction" "$target"
    else
        mbf::ai::ask "${instruction}"$'\n\n---\n'"${target}"
    fi
}

# Ask the AI CLI to generate a single shell command for `<task>` (strips markdown code fences)
# Usage: mbf::ai::cmd "find all log files larger than 100MB in /var/log"
function mbf::ai::cmd() {
    local task="$1"
    local sys_prompt="Output ONLY the exact bash command to accomplish the following task, with no explanation and no markdown fences: ${task}"
    local raw
    raw="$(mbf::ai::ask "$sys_prompt")" || return 1
    printf '%s\n' "$raw" | sed -E '/^```/d' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}
