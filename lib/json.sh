#!/usr/bin/env bash
# @mbf-module: json
# @mbf-rank: •••
# ==============================================================================
# mbf core library: json
# Zero-dependency JSON string escaping, object/array building, and key extraction
# ==============================================================================

# Escape string for safe embedding in a JSON double-quoted value
function mbf::json::escape() {
    local text="${1:-}"
    text="${text//\\/\\\\}"
    text="${text//\"/\\\"}"
    text="${text//$'\r'/}"
    text="${text//$'\n'/\\n}"
    text="${text//$'\t'/\\t}"
    printf '%s' "$text"
}

# Build a JSON object from `key=value` pairs
# - Use `key=value` for string values (automatically escaped and double-quoted)
# - Use `key:=value` for raw numeric or boolean values (e.g. `cores:=4`, `ok:=true`)
# Usage: mbf::json::object "host=web01" "cores:=4" "ok:=true"
function mbf::json::object() {
    local out="{" sep="" pair key val raw
    for pair in "$@"; do
        if [[ "$pair" == *":="* ]]; then
            key="${pair%%:=*}"
            raw="${pair#*:=}"
            out="${out}${sep}\"$(mbf::json::escape "$key")\":${raw}"
        elif [[ "$pair" == *"="* ]]; then
            key="${pair%%=*}"
            val="${pair#*=}"
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
# Handles both quoted strings (`"key": "val"`) and raw primitives (`"key": 200`).
# Usage: mbf::json::get '{"status":"ok","code":200}' "status"
function mbf::json::get() {
    local json="$1"
    local key="$2"
    printf '%s\n' "$json" | awk -v k="\"${key}\"" '
    {
        # 1. Locate `"key"` in the current line
        idx = index($0, k)
        if (idx > 0) {
            # 2. Slice everything after `"key"` and strip the leading `: `
            rest = substr($0, idx + length(k))
            sub(/^[[:space:]]*:[[:space:]]*/, "", rest)

            # 3a. If value starts with `"`, read until the first unescaped closing `"`
            if (substr(rest, 1, 1) == "\"") {
                rest = substr(rest, 2)
                if (match(rest, /(\\.|[^"\\])*"/)) {
                    val = substr(rest, 1, RLENGTH - 1)
                    gsub(/\\"/, "\"", val)
                    gsub(/\\\\/, "\\", val)
                    print val
                    exit 0
                }
            } else {
                # 3b. Unquoted number, boolean, or null: read until `,`, `}`, or whitespace
                sub(/[,}[:space:]].*$/, "", rest)
                print rest
                exit 0
            }
        }
    }
    '
}
