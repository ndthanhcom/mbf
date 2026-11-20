#!/usr/bin/env bash
# @mbf-module: ai
# @mbf-api: 1
# mbf:requires log exec json net
# ==============================================================================
# mbf plugin: ai
# Production-ready AI CLI & HTTP API integration for DevOps automation
#
# Supported Providers (priority order):
#   1. Mainstream CLIs : `agy`, `claude`, `gemini`, `codex`
#   2. Local / Agents  : `hermes`, `ollama`, `llm`
#   3. HTTP APIs (`api`): OpenAI-compatible (`MBF_AI_BASE_URL` + `OPENAI_API_KEY`),
#                         Gemini (`GEMINI_API_KEY`), Anthropic (`ANTHROPIC_API_KEY`)
#
# Environment Variables:
#   MBF_AI_PROVIDER          : Force provider (`agy`, `claude`, `gemini`, `codex`, `hermes`, `ollama`, `llm`, `api`)
#   MBF_AI_MODEL             : Model override (e.g. `claude-sonnet-4`, `gemini-2.5-pro`, `llama3`)
#   MBF_AI_BASE_URL          : OpenAI-compatible API base URL (default: `https://api.openai.com/v1`)
#   MBF_AI_SYSTEM            : Optional system instruction / SRE role prepended to prompts
#   MBF_AI_CMD               : Optional custom AI executable receiving prompt as `$1`
#   MBF_AI_TIMEOUT           : Max execution time in seconds (default: 60)
#   MBF_AI_MAX_CONTEXT_BYTES : Max context bytes read from files/stdin (default: 32768; 0 = unlimited)
#   MBF_AI_REDACT            : Set to "1" (default) to scrub secrets before sending prompts to LLMs
# ==============================================================================

# mbf:state_start
MBF_AI_PROVIDER="${MBF_AI_PROVIDER:-}"
MBF_AI_MODEL="${MBF_AI_MODEL:-}"
MBF_AI_BASE_URL="${MBF_AI_BASE_URL:-https://api.openai.com/v1}"
MBF_AI_SYSTEM="${MBF_AI_SYSTEM:-}"
MBF_AI_TIMEOUT="${MBF_AI_TIMEOUT:-60}"
MBF_AI_MAX_CONTEXT_BYTES="${MBF_AI_MAX_CONTEXT_BYTES:-32768}"
MBF_AI_REDACT="${MBF_AI_REDACT:-1}"
# mbf:state_end

# Detect active AI provider in priority order
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
    for cli in agy claude gemini codex; do
        if command -v "$cli" >/dev/null 2>&1; then
            printf '%s\n' "$cli"
            return 0
        fi
    done

    for cli in hermes ollama llm; do
        if command -v "$cli" >/dev/null 2>&1; then
            printf '%s\n' "$cli"
            return 0
        fi
    done

    if [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${GEMINI_API_KEY:-}" ] || [ -n "${OPENAI_API_KEY:-}" ]; then
        printf 'api\n'
        return 0
    fi

    printf 'none\n'
    return 1
}

# Check if an AI provider is available; print setup instructions if missing
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

    mbf::log::warn "No AI CLI tool detected (${pref:-agy, claude, gemini, codex})."
    cat <<'EOF'
=== AI CLI Installation Guide ===
  * Antigravity : agy --version (install via Google Antigravity IDE / CLI)
  * Claude Code : npm install -g @anthropic-ai/claude-code
  * Gemini CLI  : npm install -g @google/gemini-cli
  * OpenAI Codex: npm install -g @openai/codex
  * Or export OPENAI_API_KEY (with optional MBF_AI_BASE_URL), GEMINI_API_KEY, or ANTHROPIC_API_KEY.
EOF
    return 1
}

# Internal helper: scrub registered `MBF_LOG_REDACT` secrets and common credential patterns
# before transmitting logs or configs to an external AI provider.
function _mbf_ai_sanitize() {
    local text="$1"
    if [ "${MBF_AI_REDACT:-1}" != "1" ]; then
        printf '%s' "$text"
        return 0
    fi
    if declare -F _mbf_log_mask >/dev/null 2>&1; then
        text="$(_mbf_log_mask "$text")"
    fi
    printf '%s' "$text" | sed -E \
        -e 's/(Bearer[[:space:]]+)[A-Za-z0-9._~+\/=-]{8,}/\1***/g' \
        -e 's/\bsk-[A-Za-z0-9_-]{16,}/***/g' \
        -e 's/\bghp_[A-Za-z0-9]{20,}/***/g' \
        -e 's/\bAKIA[0-9A-Z]{16}/***/g' \
        -e 's/([Pp]assword|[Pp]asswd|[Ss]ecret|[Aa]pi[_-]?[Kk]ey)([[:space:]]*[:=][[:space:]]*)[^[:space:]"'\'';,]+/\1\2***/g'
}

# Internal helper: read context from `-` (stdin) or file, capping at `MBF_AI_MAX_CONTEXT_BYTES`
# (keeps the tail of large logs where recent errors occur).
function _mbf_ai_read_context() {
    local source_arg="$1"
    local max_bytes="${MBF_AI_MAX_CONTEXT_BYTES:-32768}"
    local raw=""

    if [ "$source_arg" == "-" ]; then
        raw="$(cat)"
    else
        raw="$(cat "$source_arg")"
    fi

    if [ "$max_bytes" -gt 0 ] && [ "${#raw}" -gt "$max_bytes" ]; then
        mbf::log::warn "mbf::ai: context truncated from ${#raw} to last ${max_bytes} bytes (set MBF_AI_MAX_CONTEXT_BYTES to adjust)"
        raw="[... truncated to last ${max_bytes} bytes ...]"$'\n'"$(printf '%s' "$raw" | tail -c "$max_bytes")"
    fi
    printf '%s' "$raw"
}

# Internal helper: extract response text using `jq` when installed, falling back to `mbf::json::get`
function _mbf_ai_extract_response() {
    local resp="$1"
    local jq_expr="$2"
    local fallback_key="$3"

    if command -v jq >/dev/null 2>&1; then
        local val
        if val="$(printf '%s' "$resp" | jq -r "$jq_expr // empty" 2>/dev/null)" && [ -n "$val" ]; then
            printf '%s\n' "$val"
            return 0
        fi
    fi
    mbf::json::get "$resp" "$fallback_key"
}

# Internal helper: Direct HTTP API fallback via `lib/net.sh` (headers, timeouts, curl/wget).
# Supports any OpenAI-compatible endpoint via `MBF_AI_BASE_URL` (OpenAI, OpenRouter, LiteLLM,
# Groq, DeepSeek, Azure, vLLM, Ollama), plus Gemini and Anthropic APIs.
function _mbf_ai_api_call() {
    local prompt="$1"
    local esc_prompt esc_sys payload resp
    esc_prompt="$(mbf::json::escape "$prompt")"
    esc_sys="$(mbf::json::escape "${MBF_AI_SYSTEM:-}")"

    if [ -n "${OPENAI_API_KEY:-}" ]; then
        local model="${MBF_AI_MODEL:-gpt-4o-mini}"
        local base_url="${MBF_AI_BASE_URL:-https://api.openai.com/v1}"
        base_url="${base_url%/}"
        if [ -n "$esc_sys" ]; then
            payload="{\"model\":\"${model}\",\"messages\":[{\"role\":\"system\",\"content\":\"${esc_sys}\"},{\"role\":\"user\",\"content\":\"${esc_prompt}\"}]}"
        else
            payload="{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":\"${esc_prompt}\"}]}"
        fi
        resp="$(
            mbf::net::headers_clear
            mbf::net::header_add "Authorization: Bearer ${OPENAI_API_KEY}"
            export MBF_HTTP_MAX_TIME="${MBF_AI_TIMEOUT:-60}"
            mbf::net::post_json "${base_url}/chat/completions" "$payload"
        )" || return 1
        _mbf_ai_extract_response "$resp" '.choices[0].message.content' "content"
    elif [ -n "${GEMINI_API_KEY:-}" ]; then
        local model="${MBF_AI_MODEL:-gemini-2.5-flash}"
        local full_prompt="$esc_prompt"
        [ -n "$esc_sys" ] && full_prompt="${esc_sys}\\n\\n${esc_prompt}"
        payload="{\"contents\":[{\"parts\":[{\"text\":\"${full_prompt}\"}]}]}"
        resp="$(
            mbf::net::headers_clear
            mbf::net::header_add "x-goog-api-key: ${GEMINI_API_KEY}"
            export MBF_HTTP_MAX_TIME="${MBF_AI_TIMEOUT:-60}"
            mbf::net::post_json "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent" "$payload"
        )" || return 1
        _mbf_ai_extract_response "$resp" '.candidates[0].content.parts[0].text' "text"
    elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        local model="${MBF_AI_MODEL:-claude-3-5-haiku-latest}"
        local sys_field=""
        [ -n "$esc_sys" ] && sys_field="\"system\":\"${esc_sys}\","
        payload="{\"model\":\"${model}\",${sys_field}\"max_tokens\":2048,\"messages\":[{\"role\":\"user\",\"content\":\"${esc_prompt}\"}]}"
        resp="$(
            mbf::net::headers_clear
            mbf::net::header_add "x-api-key: ${ANTHROPIC_API_KEY}"
            mbf::net::header_add "anthropic-version: 2023-06-01"
            export MBF_HTTP_MAX_TIME="${MBF_AI_TIMEOUT:-60}"
            mbf::net::post_json "https://api.anthropic.com/v1/messages" "$payload"
        )" || return 1
        _mbf_ai_extract_response "$resp" '.content[0].text' "text"
    else
        mbf::log::error "mbf::ai: no API key set for HTTP fallback"
        return 1
    fi
}

# Internal helper: populate `_MBF_AI_ARGV` for `<provider>` and `<prompt>`
function _mbf_ai_build_cmd() {
    local provider="$1"
    local prompt="$2"
    local model="${MBF_AI_MODEL:-}"
    _MBF_AI_ARGV=()

    case "$provider" in
        custom)
            _MBF_AI_ARGV=("$MBF_AI_CMD" "$prompt")
            ;;
        claude)
            _MBF_AI_ARGV=(claude)
            [ -n "$model" ] && _MBF_AI_ARGV+=(--model "$model")
            _MBF_AI_ARGV+=(-p "$prompt")
            ;;
        agy)
            _MBF_AI_ARGV=(agy -p "$prompt")
            ;;
        gemini)
            _MBF_AI_ARGV=(gemini)
            [ -n "$model" ] && _MBF_AI_ARGV+=(-m "$model")
            _MBF_AI_ARGV+=(-p "$prompt")
            ;;
        codex)
            _MBF_AI_ARGV=(codex exec)
            [ -n "$model" ] && _MBF_AI_ARGV+=(-m "$model")
            _MBF_AI_ARGV+=("$prompt")
            ;;
        hermes)
            _MBF_AI_ARGV=(hermes chat)
            [ -n "$model" ] && _MBF_AI_ARGV+=(--model "$model")
            _MBF_AI_ARGV+=(-q "$prompt")
            ;;
        ollama)
            _MBF_AI_ARGV=(ollama run "${model:-llama3}" "$prompt")
            ;;
        llm)
            _MBF_AI_ARGV=(llm)
            [ -n "$model" ] && _MBF_AI_ARGV+=(-m "$model")
            _MBF_AI_ARGV+=("$prompt")
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

# Send a non-interactive prompt (plus optional context file or `-` for stdin) to the active AI provider.
# Automatically truncates oversized context (`MBF_AI_MAX_CONTEXT_BYTES`), scrubs secrets (`MBF_AI_REDACT=1`),
# and enforces `MBF_AI_TIMEOUT`.
# Usage: mbf::ai::ask "<prompt>" [context_file_or_dash]
function mbf::ai::ask() {
    local base_prompt="${1:-}"
    local context_file="${2:-}"

    if [ -z "$base_prompt" ]; then
        mbf::log::error "mbf::ai::ask: prompt is required"
        return 1
    fi

    local context_body="" context_label=""
    if [ "$context_file" == "-" ]; then
        context_body="$(_mbf_ai_read_context "-")"
        context_label="stdin"
    elif [ -n "$context_file" ]; then
        if [ ! -f "$context_file" ]; then
            mbf::log::error "mbf::ai::ask: context file not found: $context_file"
            return 1
        fi
        context_body="$(_mbf_ai_read_context "$context_file")"
        context_label="$(basename "$context_file")"
    fi

    local prompt="$base_prompt"
    if [ -n "$context_body" ]; then
        prompt="${prompt}"$'\n\n--- Context ('"${context_label}"') ---\n'"${context_body}"
    fi
    prompt="$(_mbf_ai_sanitize "$prompt")"

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
        mbf::log::info "[DRYRUN] Would query AI provider '$provider': ${base_prompt%%$'\n'*}"
        return 0
    fi

    if [ "$provider" == "api" ]; then
        _mbf_ai_api_call "$prompt"
        return $?
    fi

    local cli_prompt="$prompt"
    if [ -n "${MBF_AI_SYSTEM:-}" ]; then
        cli_prompt="System: ${MBF_AI_SYSTEM}"$'\n\n'"${prompt}"
    fi

    local -a _MBF_AI_ARGV=()
    if ! _mbf_ai_build_cmd "$provider" "$cli_prompt"; then
        mbf::log::error "Unsupported AI provider: $provider"
        return 1
    fi

    # Guard against Linux MAX_ARG_STRLEN (128 KB): keep the short instruction on argv
    # and pipe only the context body over stdin so the user's instruction is never lost.
    if [ "${#cli_prompt}" -gt 65536 ]; then
        local short_instr="$base_prompt"
        [ -n "${MBF_AI_SYSTEM:-}" ] && short_instr="System: ${MBF_AI_SYSTEM}"$'\n\n'"${base_prompt}"
        local last_idx=$(( ${#_MBF_AI_ARGV[@]} - 1 ))
        _MBF_AI_ARGV[$last_idx]="$short_instr"
        local sanitized_ctx
        sanitized_ctx="$(_mbf_ai_sanitize "${context_body:-$prompt}")"
        printf '%s\n' "$sanitized_ctx" | mbf::exec::timeout "${MBF_AI_TIMEOUT:-60}" "${_MBF_AI_ARGV[@]}"
    else
        mbf::exec::timeout "${MBF_AI_TIMEOUT:-60}" "${_MBF_AI_ARGV[@]}"
    fi
}

# Request a structured JSON response from the active AI provider (strips markdown fences
# and validates the output starts with `{` or `[` for reliable DevOps script branching).
# Usage: mbf::ai::ask_json "<prompt>" [context_file_or_dash]
function mbf::ai::ask_json() {
    local prompt="${1:-}"
    local context_file="${2:-}"
    if [ -z "$prompt" ]; then
        mbf::log::error "mbf::ai::ask_json: prompt is required"
        return 1
    fi

    local json_prompt="Respond with ONLY valid raw JSON (no markdown fences, no commentary): ${prompt}"
    local raw cleaned
    if [ -n "$context_file" ]; then
        raw="$(mbf::ai::ask "$json_prompt" "$context_file")" || return 1
    else
        raw="$(mbf::ai::ask "$json_prompt")" || return 1
    fi
    mbf::is_dryrun && return 0

    cleaned="$(printf '%s\n' "$raw" | sed -E '/^[[:space:]]*```/d')"
    cleaned="${cleaned#"${cleaned%%[![:space:]]*}"}"
    cleaned="${cleaned%"${cleaned##*[![:space:]]}"}"

    if [[ "$cleaned" != \{* ]] && [[ "$cleaned" != \[* ]]; then
        mbf::log::error "mbf::ai::ask_json: provider did not return valid JSON"
        return 1
    fi
    printf '%s\n' "$cleaned"
}

# Analyze a log file, piped stdin (`-`), or text string and return root-cause & fix steps
# Usage: mbf::ai::analyze <file_or_dash_or_text> [custom_instruction]
function mbf::ai::analyze() {
    local target="${1:--}"
    local instruction="${2:-Analyze the following output, identify root causes of any errors or risks, and provide concise remediation steps.}"

    if [ "$target" == "-" ]; then
        mbf::ai::ask "$instruction" "-"
    elif [ -f "$target" ]; then
        mbf::ai::ask "$instruction" "$target"
    else
        mbf::ai::ask "${instruction}"$'\n\n---\n'"${target}"
    fi
}

# Ask the AI provider to generate a single shell command for `<task>` (strips markdown code fences)
# Usage: mbf::ai::cmd "find all log files larger than 100MB in /var/log"
function mbf::ai::cmd() {
    local task="$1"
    local sys_prompt="Output ONLY the exact bash command to accomplish the following task, with no explanation and no markdown fences: ${task}"
    local raw
    raw="$(mbf::ai::ask "$sys_prompt")" || return 1
    printf '%s\n' "$raw" | sed -E '/^```/d' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Safe human-in-the-loop AI command runner: generates a command via `mbf::ai::cmd`,
# displays it, requires explicit confirmation (`mbf::exec::confirm`, default `n`),
# and executes it via `mbf::exec::run` (respecting `MBF_DRYRUN=1` and `MBF_YES=1`).
# Usage: mbf::ai::run "find all log files larger than 100MB in /var/log"
function mbf::ai::run() {
    local task="${1:-}"
    if [ -z "$task" ]; then
        mbf::log::error "mbf::ai::run: task description is required"
        return 1
    fi

    local suggested
    suggested="$(mbf::ai::cmd "$task")" || return 1
    if [ -z "$suggested" ]; then
        mbf::log::error "mbf::ai::run: AI provider returned an empty command"
        return 1
    fi

    printf 'Suggested command:\n  %s\n' "$suggested" >&2
    if ! mbf::exec::confirm "Execute this command?" "n"; then
        mbf::log::warn "Execution cancelled by user."
        return 1
    fi

    mbf::exec::run bash -c "$suggested"
}
