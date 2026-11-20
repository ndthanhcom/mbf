# Library: `json` — Zero-Dependency JSON Builder & Parser

`lib/json.sh` builds and queries JSON payloads for webhooks, REST APIs, and server telemetry without requiring `jq`, Python, or Node.js on the target host.

---

## Function Reference & Examples

### 1. `mbf::json::object "key=str" "num:=42" "flag:=true"`
Builds a single-line JSON object from arguments:
- **`key=value`**: Automatically escapes and double-quotes `<value>` as a JSON string.
- **`key:=value`**: Emits `<value>` as a raw JSON number, boolean, null, or nested JSON value.
- Only the end of `<key>` is checked for `:=`, so string values can safely contain `:=` (such as URLs).

```bash
mbf::use json

payload="$(mbf::json::object \
    "host=prod-web01" \
    "url=https://shop.example.com/?filter:=active" \
    "cpu_cores:=8" \
    "healthy:=true")"

echo "$payload"
# Output: {"host":"prod-web01","url":"https://shop.example.com/?filter:=active","cpu_cores":8,"healthy":true}
```

### 2. `mbf::json::array "item1" "item2" ...` & `mbf::json::array_raw '<raw1>' '<raw2>' ...`
- `array`: Builds a JSON array of escaped strings from arguments.
- `array_raw`: Builds a JSON array of pre-formatted raw JSON values (numbers, booleans, nested objects/arrays).

```bash
services_json="$(mbf::json::array "nginx" "php8.2-fpm" "redis-server" "varnish")"
# Output: ["nginx","php8.2-fpm","redis-server","varnish"]

ports_json="$(mbf::json::array_raw 80 443)"
# Output: [80,443]

nodes_json="$(mbf::json::array_raw \
    "$(mbf::json::object "host=web01" "active:=true")" \
    "$(mbf::json::object "host=web02" "active:=false")")"
# Output: [{"host":"web01","active":true},{"host":"web02","active":false}]
```

### 3. `mbf::json::get <json_string> <key> [default]` & `mbf::json::has <json_string> <key>`
- `get`: Extracts the scalar value of `<key>` from a JSON string (decoding `\"`, `\\`, `\n`, `\t`, and `\/`). Works for both quoted strings and unquoted numbers/booleans. Prints optional `[default]` when `<key>` is absent.
- `has`: Returns `0` if `<key>` exists in `<json_string>`, `1` otherwise.

```bash
resp='{"status":"completed","workers":4,"message":"Reloaded \"nginx\" successfully"}'

status="$(mbf::json::get "$resp" "status")"           # -> completed
workers="$(mbf::json::get "$resp" "workers")"         # -> 4
region="$(mbf::json::get "$resp" "region" "us-east")" # -> us-east (fallback)
msg="$(mbf::json::get "$resp" "message")"             # -> Reloaded "nginx" successfully

if mbf::json::has "$resp" "workers"; then
    mbf::log::info "Worker count present: ${workers}"
fi
```

### 4. `mbf::json::merge <json_obj1> <json_obj2> [...]`
Shallow-merges two or more JSON objects into a single compact JSON object.

```bash
base="$(mbf::json::object "env=prod" "service=api")"
meta="$(mbf::json::object "release=v2.4.0" "dry_run:=false")"
payload="$(mbf::json::merge "$base" "$meta")"
# Output: {"env":"prod","service":"api","release":"v2.4.0","dry_run":false}
```

### 5. `mbf::json::is_valid <json_string>` & `mbf::json::pretty <json_string>`
- `is_valid`: Returns `0` if `<json_string>` is valid JSON, `1` otherwise (uses `jq` → `python3` → pure-Bash structural fallback).
- `pretty`: Pretty-prints compact JSON with 2-space indentation (`jq .` → `python3` → pure-`awk` fallback).

```bash
if mbf::json::is_valid "$resp"; then
    mbf::json::pretty "$resp"
fi
```

### 6. `mbf::json::escape <string>`
Escapes backslashes, double quotes, newlines, tabs, and control characters so `<string>` can be embedded safely inside a double-quoted JSON value.

```bash
raw_text=$'Line 1: "Error"\nLine 2: C:\\temp'
escaped="$(mbf::json::escape "$raw_text")"
echo "$escaped"
# Output: Line 1: \"Error\"\nLine 2: C:\\temp
```
