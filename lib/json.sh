#!/usr/bin/env bash
# @mbf-module: json
# ==============================================================================
# mbf core library: json
# Zero-dependency JSON string escaping, object/array building, and key extraction
#
# Scope (by design, to stay jq-free and tiny):
#   - Builders (`object`, `array`) always produce valid single-line JSON.
#   - `get` is a pragmatic extractor, NOT a full parser: it returns the FIRST
#     `"key": value` found anywhere in the text (no nested paths), and works on
#     JSON that keeps each key/value pair on one line. Use `jq` for complex data.
# ==============================================================================

# Escape string for safe embedding in a JSON double-quoted value
function mbf::json::escape() {
    local text="${1:-}"
    text="${text//\\/\\\\}"
    text="${text//\"/\\\"}"
    text="${text//$'\r'/\\r}"
    text="${text//$'\n'/\\n}"
    text="${text//$'\t'/\\t}"
    text="${text//$'\b'/\\b}"
    text="${text//$'\f'/\\f}"
    printf '%s' "$text"
}

# Build a JSON object from `key=value` pairs
# - Use `key=value` for string values (automatically escaped and double-quoted)
# - Use `key:=value` for raw numeric or boolean values (e.g. `cores:=4`, `ok:=true`)
# Only the KEY part decides the form, so string values may safely contain `:=`.
# Usage: mbf::json::object "host=web01" "cores:=4" "ok:=true"
function mbf::json::object() {
    local out="{" sep="" pair key val
    for pair in "$@"; do
        [[ "$pair" == *"="* ]] || continue
        key="${pair%%=*}"
        val="${pair#*=}"
        if [[ "$key" == *":" ]]; then
            # `name:=raw` -> key is `name:`, emit value unquoted
            out="${out}${sep}\"$(mbf::json::escape "${key%:}")\":${val}"
        else
            out="${out}${sep}\"$(mbf::json::escape "$key")\":\"$(mbf::json::escape "$val")\""
        fi
        sep=","
    done
    printf '%s}\n' "$out"
}

# Build a JSON array of strings from arguments
# Usage: mbf::json::array "nginx" "mysql" "redis"
function mbf::json::array() {
    local out="[" sep="" item
    for item in "$@"; do
        out="${out}${sep}\"$(mbf::json::escape "$item")\""
        sep=","
    done
    printf '%s]\n' "$out"
}

# Extract a scalar value by key from a JSON string without requiring `jq`
# Handles quoted strings (`"key": "val"`, with escaped `\"`, `\\`, `\n`, `\t`, `\/`)
# and raw primitives (`"key": 200`, `true`, `null`). Prints nothing (and still
# returns 0, for backward compatibility) when the key is absent.
# Usage: mbf::json::get '{"status":"ok","code":200}' "status"
function mbf::json::get() {
    local json="$1"
    local key="$2"
    printf '%s\n' "$json" | MBF_K="\"${key}\"" awk '
    BEGIN { k = ENVIRON["MBF_K"] }
    {
        # 1. Locate `"key"` in the current line, followed by `:`
        line = $0
        while ((idx = index(line, k)) > 0) {
            rest = substr(line, idx + length(k))
            line = rest
            if (rest !~ /^[[:space:]]*:/) continue
            sub(/^[[:space:]]*:[[:space:]]*/, "", rest)

            # 2a. Quoted value: read until the first unescaped closing `"`
            if (substr(rest, 1, 1) == "\"") {
                rest = substr(rest, 2)
                if (match(rest, /(\\.|[^"\\])*"/)) {
                    val = substr(rest, 1, RLENGTH - 1)
                    # Decode escapes; `\\` is protected first so `\\n` stays `\n` text
                    gsub(/\\\\/, "\001", val)
                    gsub(/\\"/, "\"", val)
                    gsub(/\\n/, "\n", val)
                    gsub(/\\t/, "\t", val)
                    gsub(/\\r/, "\r", val)
                    gsub(/\\\//, "/", val)
                    gsub(/\001/, "\\", val)
                    print val
                    exit
                }
            } else {
                # 2b. Unquoted number, boolean, or null: read until `,`, `}`, `]` or whitespace
                sub(/[],}[:space:]].*$/, "", rest)
                print rest
                exit
            }
        }
    }
    '
}
