# Plugin: `ai` `[•••]` — Mainstream AI CLI Integration

`plugins/ai.sh` connects `mbf` scripts to AI CLI tools non-interactively so your scripts can analyze error logs, review server audits, summarize CI build failures, or generate shell commands.

---

## Provider Priority Order

`mbf::ai::detect` selects the first available provider in this order:
1. **Mainstream Coding & Ops CLIs (Primary)**:
   - `claude` — Claude Code CLI (`claude -p "<prompt>"`)
   - `agy` — Google Antigravity CLI (`agy -p "<prompt>"`)
   - `gemini` — Google Gemini CLI (`gemini -p "<prompt>"`)
   - `codex` — OpenAI Codex CLI (`codex exec "<prompt>"`)
2. **Secondary Agent / Local Fallbacks**:
   - `hermes` (`hermes chat -q "<prompt>"`)
   - `ollama` (`ollama run llama3 "<prompt>"`)
   - `llm` (`llm "<prompt>"`)
3. **Zero-CLI HTTP API Fallback (`api`)**:
   - Triggered automatically when `OPENAI_API_KEY`, `GEMINI_API_KEY`, or `ANTHROPIC_API_KEY` is exported in the environment.

---

## Environment Variables

| Variable | Description |
| :--- | :--- |
| `MBF_AI_PROVIDER` | Force a specific provider (`claude`, `agy`, `gemini`, `codex`, `hermes`, `ollama`, `llm`, `api`). |
| `MBF_AI_MODEL` | Optional model name override (e.g., `claude-sonnet-4-20250514`, `gemini-2.5-pro`, `llama3`). |
| `MBF_AI_BASE_URL` | OpenAI-compatible API base URL (default: `https://api.openai.com/v1` — works with OpenRouter, LiteLLM, Groq, Azure, DeepSeek, vLLM, Ollama). |
| `MBF_AI_SYSTEM` | Optional system instruction / SRE role prepended to prompts. |
| `MBF_AI_CMD` | Optional custom executable receiving the prompt string as `$1`. |
| `MBF_AI_TIMEOUT` | Maximum execution timeout in seconds (default: `60`). |
| `MBF_AI_MAX_CONTEXT_BYTES` | Maximum context bytes read from files or stdin before tail-truncating (default: `32768`; `0` = unlimited). |
| `MBF_AI_REDACT` | Set to `"1"` (default) to scrub `MBF_LOG_REDACT` secrets and common credentials (`Bearer`, `sk-`, `ghp_`, `AKIA`, `password=...`) before sending to any LLM. |

---

## Function Reference & Examples

### 1. `mbf::ai::detect`
Prints the name of the highest-priority detected AI provider (`claude`, `agy`, `gemini`, `codex`, `hermes`, `ollama`, `llm`, `api`), or returns `1` (`none`) if none is available.

```bash
mbf::use ai

provider="$(mbf::ai::detect)"
mbf::log::info "Active AI provider: ${provider}"
```

### 2. `mbf::ai::ensure [preferred_provider]`
Verifies that any supported AI provider (or `[preferred_provider]`) is installed. If missing, logs a warning, prints installation instructions for `claude`, `agy`, `gemini`, and `codex`, and returns `1`.

```bash
mbf::ai::ensure || exit 1

# Or require a specific CLI tool:
mbf::ai::ensure "claude" || exit 1
```

### 3. `mbf::ai::ask "<prompt>" [context_file_or_dash]`
Sends a non-interactive prompt to the active AI provider.
- Pass a file path as the second argument to attach the file's contents.
- Pass `-` as the second argument to attach piped `stdin`.
- Prompts larger than 64 KB are automatically piped over `stdin` to avoid the Linux `MAX_ARG_STRLEN` (128 KB) command-line limit.

```bash
# 1. Simple prompt
mbf::ai::ask "Explain the difference between Nginx fastcgi_read_timeout and proxy_read_timeout."

# 2. Prompt with an attached configuration file
mbf::ai::ask "Review this Nginx config for security or performance issues" "/etc/nginx/nginx.conf"

# 3. Prompt with piped standard input (`-`)
tail -n 50 /var/log/nginx/error.log | mbf::ai::ask "Summarize the top errors in this log" -
```

### 4. `mbf::ai::analyze <file_or_dash_or_text> [custom_instruction]`
High-level helper for root-cause analysis and remediation steps. Accepts a file path, `-` (piped `stdin`), or an inline text string.

```bash
# Analyze a log file with default root-cause prompt
mbf::ai::analyze "/var/log/mysql/error.log"

# Analyze piped output with a custom instruction
dmesg -T | tail -n 100 | mbf::ai::analyze - "Check for OOM killer events and recommend memory limits."
```

### 5. `mbf::ai::cmd "<task_description>"`
Requests a single executable Bash command for `<task_description>` with markdown code fences (` ```bash ... ``` `) and explanations stripped.

```bash
suggested_cmd="$(mbf::ai::cmd "find all .log files in /var/log modified more than 14 days ago")"
echo "Suggested command: ${suggested_cmd}"
```

### 6. `mbf::ai::ask_json "<prompt>" [context_file_or_dash]`
Requests a machine-readable raw JSON response (strips markdown fences and validates `{...}` or `[...]`) so DevOps scripts can branch reliably using `mbf::json::get` or `jq`.

```bash
res="$(mbf::ai::ask_json 'Return {"severity":"low|high","restart":true|false} for this log' /var/log/nginx/error.log)"
severity="$(mbf::json::get "$res" "severity")"
```

### 7. `mbf::ai::run "<task_description>"`
Safe human-in-the-loop command runner: generates a command via `mbf::ai::cmd`, prints it to stderr, requires explicit confirmation via `mbf::exec::confirm` (defaults to `n`; never auto-runs in `CI=1` unless `MBF_YES=1`), and runs it via `mbf::exec::run`.

```bash
mbf::ai::run "show the 10 largest files in /var/log"
```

### CLI Shortcut (`mbf ai`)
```bash
tail -n 100 /var/log/nginx/error.log | mbf ai analyze -
mbf ai ask-json 'Return {"ok":true}'
```
