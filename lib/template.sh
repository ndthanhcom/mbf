#!/usr/bin/env bash
# @mbf-module: template
# @mbf-rank: •••
# mbf:requires log
# ==============================================================================
# mbf core library: template
# Convention-based template resolution (`lib/templates/` + user `templates/`),
# variable validation (`# @mbf-vars:`), `{{VAR}}` rendering & atomic file writes
#
# Rendering semantics:
#   - Variables listed in `# @mbf-vars: VAR1 VAR2` are required by `validate_vars`
#     and `render` (missing required variables return 1 before writing the file).
#   - In `render_str`, explicit `KEY=val` arguments are applied first, then any
#     remaining `{{VAR}}` placeholders fall back to current shell variables
#     (or render as empty string if unset).
#   - Replacement values are inserted literally: `&`, `\`, `|`, and URLs with
#     query strings are preserved intact across Bash 4.x and Bash 5.2+.
# ==============================================================================

# mbf:state_start
MBF_TEMPLATE_PATH="${MBF_TEMPLATE_PATH:-}"
# mbf:state_end

# Resolve a template name or path to an existing `.tpl` file:
# 1. Direct relative/absolute file path
# 2. Directories in MBF_TEMPLATE_PATH and `<MBF_SCRIPT_DIR>/templates/` (user override)
# 3. Built-in `<MBF_HOME>/lib/templates/`
# Usage: mbf::template::resolve "nginx/vhost-php.conf"
function mbf::template::resolve() {
    local name="$1"
    local caller_dir="${MBF_SCRIPT_DIR:-.}"
    local -a candidates=("$name")
    [[ "$name" != *.tpl ]] && candidates+=("${name}.tpl")

    local cand
    # 1. Direct path
    for cand in "${candidates[@]}"; do
        if [ -f "$cand" ]; then
            mbf::log::debug_ext "Template '$name' resolved to direct path '$cand'"
            printf '%s\n' "$cand"
            return 0
        fi
    done

    # 2. Custom template directories (MBF_TEMPLATE_PATH + caller script's templates/)
    local search_dirs="${MBF_TEMPLATE_PATH:+${MBF_TEMPLATE_PATH}:}${caller_dir}/templates"
    local IFS=':' t_dir
    for t_dir in $search_dirs; do
        [ -z "$t_dir" ] && continue
        for cand in "${candidates[@]}"; do
            if [ -f "${t_dir}/${cand}" ]; then
                mbf::log::debug_ext "Template '$name' resolved to custom template '${t_dir}/${cand}'"
                printf '%s\n' "${t_dir}/${cand}"
                return 0
            fi
        done
    done

    # 3. Built-in MBF templates in lib/templates/
    if [ -n "${MBF_HOME:-}" ]; then
        for cand in "${candidates[@]}"; do
            if [ -f "${MBF_HOME}/lib/templates/${cand}" ]; then
                mbf::log::debug_ext "Template '$name' resolved to built-in '${MBF_HOME}/lib/templates/${cand}'"
                printf '%s\n' "${MBF_HOME}/lib/templates/${cand}"
                return 0
            fi
        done
    fi

    mbf::log::debug_ext "Failed to resolve template '$name' (MBF_TEMPLATE_PATH='${MBF_TEMPLATE_PATH:-}', MBF_SCRIPT_DIR='${caller_dir}')"
    return 1
}

# Validate that all variables listed in `# @mbf-vars: VAR1 VAR2` are provided in args or env
# Usage: mbf::template::validate_vars <tpl_file> [KEY1=val1 ...]
function mbf::template::validate_vars() {
    local tpl_file="$1"
    shift 1 2>/dev/null || true

    local resolved
    resolved="$(mbf::template::resolve "$tpl_file")" || {
        mbf::log::error "mbf::template::validate_vars: template not found: $tpl_file"
        return 1
    }

    local req_vars
    req_vars="$(grep -m1 '^# @mbf-vars:' "$resolved" 2>/dev/null | sed 's/^# @mbf-vars:[[:space:]]*//' || true)"
    [ -z "$req_vars" ] && return 0

    local var pair found
    for var in $req_vars; do
        var="${var%$'\r'}"
        found=0
        if [ -n "${!var:-}" ]; then
            found=1
        else
            for pair in "$@"; do
                if [[ "$pair" == "${var}="* ]]; then
                    found=1
                    break
                fi
            done
        fi
        if [ "$found" -eq 0 ]; then
            mbf::log::error "Template '$tpl_file' requires variable '$var' (declared in # @mbf-vars)"
            return 1
        fi
    done
    return 0
}

# Internal helper: literal string replacement safe from Bash 5.2 `patsub_replacement` (`&`)
function _mbf_template_replace_token() {
    local text="$1"
    local token="$2"
    local val="$3"
    local out="" prefix

    while [[ "$text" == *"$token"* ]]; do
        prefix="${text%%"$token"*}"
        out="${out}${prefix}${val}"
        text="${text#*"$token"}"
    done
    printf '%s%s' "$out" "$text"
}

# Render a template string in memory by replacing {{VAR}} placeholders
# Usage: mbf::template::render_str "Hello {{NAME}}" "NAME=World"
function mbf::template::render_str() {
    local content="$1"
    shift 1 2>/dev/null || true
    local pair k v

    # 1. Apply explicit KEY=val arguments first
    for pair in "$@"; do
        if [[ "$pair" == *"="* ]]; then
            k="${pair%%=*}"
            v="${pair#*=}"
            content="$(_mbf_template_replace_token "$content" "{{${k}}}" "$v")"
        fi
    done

    # 2. Replace any remaining {{VAR}} placeholders from current shell variables
    while [[ "$content" =~ \{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\} ]]; do
        k="${BASH_REMATCH[1]}"
        v="${!k:-}"
        content="$(_mbf_template_replace_token "$content" "{{${k}}}" "$v")"
    done

    printf '%s\n' "$content"
}

# Render a template (by name or file path) to `<dest_file>` atomically
# Strips optional `# @mbf-vars:` metadata line from the rendered output.
# Usage: mbf::template::render <tpl_name_or_file> <dest_file> [KEY1=val1 KEY2=val2 ...]
function mbf::template::render() {
    local tpl_arg="$1"
    local dest_file="$2"
    shift 2 2>/dev/null || true

    local tpl_file
    if ! tpl_file="$(mbf::template::resolve "$tpl_arg")"; then
        mbf::log::error "mbf::template::render: template not found: $tpl_arg"
        return 1
    fi

    mbf::template::validate_vars "$tpl_file" "$@" || return 1

    local raw_content rendered
    raw_content="$(grep -v '^# @mbf-vars:' "$tpl_file" || true)"
    rendered="$(mbf::template::render_str "$raw_content" "$@")"

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would render template $tpl_file -> $dest_file"
        return 0
    fi

    printf '%s\n' "$rendered" | mbf::template::write_atomic "$dest_file"
}

# Atomically write stdin content to `<dest_file>` via a sibling temp file + mv
# (preserves existing file mode/owner via `_mbf_replace_file` when available)
# Usage: printf '...' | mbf::template::write_atomic /etc/nginx/conf.d/site.conf
function mbf::template::write_atomic() {
    local dest_file="$1"
    local dest_dir
    dest_dir="$(dirname "$dest_file")"
    mkdir -p "$dest_dir" 2>/dev/null || return 1

    if declare -F _mbf_replace_file >/dev/null 2>&1; then
        _mbf_replace_file "$dest_file"
        return $?
    fi

    local tmp_out="${dest_file}.mbf.tmp.$$"
    cat > "$tmp_out" || { rm -f "$tmp_out"; return 1; }
    mv -f "$tmp_out" "$dest_file"
}

# List available templates across custom (MBF_TEMPLATE_PATH, ./templates) and built-in directories
function mbf::template::list() {
    local caller_dir="${MBF_SCRIPT_DIR:-.}"
    local -a roots=()
    local IFS=':' t_dir
    for t_dir in ${MBF_TEMPLATE_PATH:-}; do
        [ -n "$t_dir" ] && [ -d "$t_dir" ] && roots+=("$t_dir")
    done
    [ -d "${caller_dir}/templates" ] && roots+=("${caller_dir}/templates")
    [ -n "${MBF_HOME:-}" ] && [ -d "${MBF_HOME}/lib/templates" ] && roots+=("${MBF_HOME}/lib/templates")

    local r f
    for r in "${roots[@]}"; do
        while IFS= read -r -d $'\0' f; do
            printf '%s\n' "${f#"${r}/"}"
        done < <(find "$r" -type f -name "*.tpl" -print0 2>/dev/null | sort -z)
    done
}
