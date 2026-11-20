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

# Build a JSON array of pre-formatted raw JSON values (numbers, booleans, objects, arrays)
# Usage: mbf::json::array_raw '{"id":1}' '{"id":2}'
function mbf::json::array_raw() {
    local out="[" sep="" item
    for item in "$@"; do
        out="${out}${sep}${item}"
        sep=","
    done
    printf '%s]\n' "$out"
}

# Shallow-merge two or more JSON objects into a single compact JSON object
# Usage: mbf::json::merge '{"a":1}' '{"b":"two"}'
function mbf::json::merge() {
    local out="{" sep="" obj inner
    for obj in "$@"; do
        # Strip leading/trailing whitespace
        inner="${obj#"${obj%%[![:space:]]*}"}"
        inner="${inner%"${inner##*[![:space:]]}"}"
        # Strip outer braces if present
        [[ "$inner" == "{"* ]] && inner="${inner#\{}"
        [[ "$inner" == *"}" ]] && inner="${inner%\}}"
        inner="${inner#"${inner%%[![:space:]]*}"}"
        inner="${inner%"${inner##*[![:space:]]}"}"
        [ -z "$inner" ] && continue
        out="${out}${sep}${inner}"
        sep=","
    done
    printf '%s}\n' "$out"
}

# Return 0 if `<key>` exists in a JSON string, 1 otherwise
# Usage: mbf::json::has '{"status":"ok"}' "status"
function mbf::json::has() {
    local json="${1:-}"
    local key="${2:-}"
    [ -n "$key" ] || return 1
    printf '%s\n' "$json" | MBF_K="\"${key}\"" awk '
    BEGIN { k = ENVIRON["MBF_K"]; found = 0 }
    {
        line = $0
        while ((idx = index(line, k)) > 0) {
            rest = substr(line, idx + length(k))
            line = rest
            if (rest ~ /^[[:space:]]*:/) {
                found = 1
                exit 0
            }
        }
    }
    END { exit(found ? 0 : 1) }
    '
}

# Extract a scalar value by key from a JSON string without requiring `jq`
# Handles quoted strings (`"key": "val"`, with escaped `\"`, `\\`, `\n`, `\t`, `\/`)
# and raw primitives (`"key": 200`, `true`, `null`).
# Prints optional `[default]` when the key is absent (or nothing if omitted),
# and returns 0 for backward compatibility.
# Usage: mbf::json::get '{"status":"ok","code":200}' "status" ["unknown"]
function mbf::json::get() {
    local json="${1:-}"
    local key="${2:-}"
    local has_def=0
    local def=""
    if [ $# -ge 3 ]; then
        has_def=1
        def="$3"
    fi
    printf '%s\n' "$json" | MBF_K="\"${key}\"" MBF_HAS_DEF="$has_def" MBF_DEF="$def" awk '
    BEGIN { k = ENVIRON["MBF_K"]; found = 0 }
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
                    found = 1
                    exit
                }
            } else {
                # 2b. Unquoted number, boolean, or null: read until `,`, `}`, `]` or whitespace
                sub(/[],}[:space:]].*$/, "", rest)
                print rest
                found = 1
                exit
            }
        }
    }
    END {
        if (!found && ENVIRON["MBF_HAS_DEF"] == "1") {
            print ENVIRON["MBF_DEF"]
        }
    }
    '
}

# Validate whether a string is well-formed JSON (returns 0 if valid, 1 otherwise)
# Uses `jq` or `python3` when available, with a pure-Bash structural fallback.
# Usage: mbf::json::is_valid '{"ok":true}'
function mbf::json::is_valid() {
    local json="${1:-}"
    local trimmed="${json#"${json%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [ -n "$trimmed" ] || return 1

    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$trimmed" | jq -e . >/dev/null 2>&1
        return $?
    fi
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$trimmed" | python3 -c 'import json, sys; json.load(sys.stdin)' >/dev/null 2>&1
        return $?
    fi

    # Pure-Bash structural fallback (primitives, quoted strings, balanced objects/arrays)
    case "$trimmed" in
        true|false|null) return 0 ;;
        \"*\")
            [ "${#trimmed}" -ge 2 ] && return 0
            return 1
            ;;
        \{*\}|\[*\])
            local i c in_str=0 esc=0 depth=0 len="${#trimmed}"
            for ((i = 0; i < len; i++)); do
                c="${trimmed:i:1}"
                if [ "$in_str" -eq 1 ]; then
                    if [ "$esc" -eq 1 ]; then
                        esc=0
                    elif [ "$c" == "\\" ]; then
                        esc=1
                    elif [ "$c" == '"' ]; then
                        in_str=0
                    fi
                else
                    case "$c" in
                        '"') in_str=1 ;;
                        '{'|'[') depth=$((depth + 1)) ;;
                        '}'|']')
                            depth=$((depth - 1))
                            [ "$depth" -lt 0 ] && return 1
                            ;;
                    esac
                fi
            done
            [ "$in_str" -eq 0 ] && [ "$depth" -eq 0 ] && return 0
            return 1
            ;;
        *)
            [[ "$trimmed" =~ ^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$ ]] && return 0
            return 1
            ;;
    esac
}

# Pretty-print compact JSON with 2-space indentation
# Uses `jq` or `python3` when available, with a pure-awk fallback.
# Usage: mbf::json::pretty '{"host":"web01","ports":[80,443]}'
function mbf::json::pretty() {
    local json="${1:-}"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq .
        return $?
    fi
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$json" | python3 -c 'import json, sys; print(json.dumps(json.load(sys.stdin), indent=2))'
        return $?
    fi

    printf '%s' "$json" | awk '
    function indent(n,    i, s) { s = ""; for (i = 0; i < n; i++) s = s "  "; return s }
    {
        in_str = 0; esc = 0; level = 0; out = ""
        n = length($0)
        for (i = 1; i <= n; i++) {
            c = substr($0, i, 1)
            if (in_str) {
                out = out c
                if (esc) { esc = 0 }
                else if (c == "\\") { esc = 1 }
                else if (c == "\"") { in_str = 0 }
            } else {
                if (c ~ /[ \t\r\n]/) { continue }
                else if (c == "\"") { in_str = 1; out = out c }
                else if (c == "{" || c == "[") {
                    level++
                    out = out c "\n" indent(level)
                } else if (c == "}" || c == "]") {
                    level--
                    if (level < 0) level = 0
                    out = out "\n" indent(level) c
                } else if (c == ",") {
                    out = out ",\n" indent(level)
                } else if (c == ":") {
                    out = out ": "
                } else {
                    out = out c
                }
            }
        }
        print out
    }
    '
}
