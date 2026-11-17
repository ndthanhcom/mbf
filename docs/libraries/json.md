# Library: `json` `[•••]` — Zero-Dependency JSON Builder & Parser

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

### 2. `mbf::json::array "item1" "item2" ...`
Builds a JSON array of escaped strings from arguments.

```bash
services_json="$(mbf::json::array "nginx" "php8.2-fpm" "redis-server" "varnish")"
echo "$services_json"
# Output: ["nginx","php8.2-fpm","redis-server","varnish"]
```

### 3. `mbf::json::get <json_string> <key>`
Extracts the scalar value of `<key>` from a JSON string (decoding `\"`, `\\`, `\n`, `\t`, and `\/`). Works for both quoted strings and unquoted numbers/booleans.

```bash
resp='{"status":"completed","workers":4,"message":"Reloaded \"nginx\" successfully"}'

status="$(mbf::json::get "$resp" "status")"     # -> completed
workers="$(mbf::json::get "$resp" "workers")"   # -> 4
msg="$(mbf::json::get "$resp" "message")"       # -> Reloaded "nginx" successfully
```

### 4. `mbf::json::escape <string>`
Escapes backslashes, double quotes, newlines, tabs, and control characters so `<string>` can be embedded safely inside a double-quoted JSON value.

```bash
raw_text=$'Line 1: "Error"\nLine 2: C:\\temp'
escaped="$(mbf::json::escape "$raw_text")"
echo "$escaped"
# Output: Line 1: \"Error\"\nLine 2: C:\\temp
```
