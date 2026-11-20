#!/usr/bin/env bash
# ==============================================================================
# mbf build tool: exporter
# Fast single-pass POSIX awk tree-shaking bundler for standalone scripts & bundles
# Supports custom extensions (MBF_EXT_PATH) and template bundling (`templates/`)
#
# Tree-Shaker Constraints (enforced by `mbf doctor`):
#   1. Module functions must be declared with `function name() {`.
#   2. Multi-line functions must close with `}` at column 0 on its own line
#      (single-line `function name() { ...; }` functions are also supported).
#   3. Dynamic function names built at runtime (e.g. `"mbf::plugin::${action}"`)
#      cannot be statically traced — pass `--full-module` to retain all functions.
# ==============================================================================

# Resolve module, plugin, or custom extension name to its file path
# Delegates to `_mbf_resolve_path` from `framework.sh` so resolution logic lives in one place.
function _mbf_export_find_module() {
    local raw="$1"
    local script_dir="${2:-${MBF_SCRIPT_DIR:-.}}"
    _mbf_resolve_path "$raw" "$script_dir"
}

# Recursively expand module list with `# mbf:requires` headers in topological order.
# Returns 1 immediately if any requested or required module cannot be resolved.
function _mbf_export_collect_modules() {
    local script_dir="$1"
    shift
    local -a queue=("$@")
    local -a result=("${MBF_HOME}/framework.sh" "${MBF_HOME}/lib/log.sh")
    declare -A seen=(
        ["${MBF_HOME}/framework.sh"]=1
        ["${MBF_HOME}/lib/log.sh"]=1
    )

    local idx=0 mod mod_file reqs req
    while [ "$idx" -lt "${#queue[@]}" ]; do
        mod="${queue[$idx]}"
        idx=$((idx + 1))
        [ -z "$mod" ] && continue
        if ! mod_file="$(_mbf_export_find_module "$mod" "$script_dir")"; then
            mbf::log::error "Export error: unresolved module '$mod' (searched MBF_EXT_PATH, ${script_dir}/{lib,plugins}, ${MBF_HOME}/{lib,plugins})"
            return 1
        fi
        if [ -z "${seen[$mod_file]:-}" ]; then
            seen["$mod_file"]=1
            reqs="$(_mbf_read_requires "$mod_file")"
            for req in $reqs; do
                queue+=("$req")
            done
            result+=("$mod_file")
        fi
    done

    printf '%s\n' "${result[@]}"
}

# Resolve a local non-mbf `source` file relative to the input script's directory
function _mbf_export_resolve_local_source() {
    local src_target="$1"
    local script_dir="$2"
    local clean="${src_target//[\"\']/}"
    clean="${clean//\$\{DIR\}/$script_dir}"
    clean="${clean//\$DIR/$script_dir}"
    clean="${clean//\$\{MBF_SCRIPT_DIR\}/$script_dir}"
    clean="${clean//\$MBF_SCRIPT_DIR/$script_dir}"

    if [[ "$clean" != /* ]] && [ -f "${script_dir}/${clean}" ]; then
        clean="${script_dir}/${clean}"
    fi
    if [ -f "$clean" ]; then
        printf '%s\n' "$clean"
        return 0
    fi
    return 1
}

# Single-pass POSIX awk tree-shaker:
#   Phase 1: Parse `# mbf:state_start ... # mbf:state_end` blocks and `function name() { ... }`
#            bodies from all loaded modules, plus user script body.
#   Phase 2: Tokenize function bodies using standard POSIX `match()`/`substr()` (compatible with
#            gawk, mawk, and macOS BSD awk) to build a caller -> callee graph.
#   Phase 3: Run Breadth-First Search (BFS) starting from functions referenced in the user script
#            and emit only reachable functions in declaration order.
function _mbf_export_tree_shake() {
    local full_module="$1"
    local user_file="$2"
    shift 2
    awk -v full_mode="$full_module" -v user_file="$user_file" '
    # --- Phase 1: Collect state blocks, module functions, and user script code ---
    FILENAME == user_file {
        in_user = 1
    }
    in_user {
        user_code = user_code "\n" $0
        next
    }
    /^# mbf:state_start/ { in_state = 1; next }
    /^# mbf:state_end/   { in_state = 0; next }
    in_state {
        if ($0 !~ /^MBF_HOME=/ && $0 !~ /^MBF_LOADED_MODULES=/ && $0 !~ /^MBF_SCRIPT_DIR=/) {
            state_lines[++state_count] = $0
        }
        next
    }
    /^[[:space:]]*function[[:space:]]+[a-zA-Z0-9_:]+[[:space:]]*(\(\))?[[:space:]]*\{/ {
        line = $0
        sub(/^[[:space:]]*function[[:space:]]+/, "", line)
        sub(/[[:space:]]*(\(\))?[[:space:]]*\{.*$/, "", line)
        fn = line
        is_one_liner = ($0 ~ /\{.*\}[[:space:]]*$/)
        # Loader & framework update/version-switch functions are not needed in standalone exported scripts
        if (fn == "mbf::use" || fn == "mbf::is_loaded" || fn == "_mbf_resolve_path" || fn == "_mbf_read_requires" || fn == "mbf::check_update" || fn == "_mbf_version_gt" || fn == "mbf::update" || fn == "mbf::list_versions" || fn == "mbf::switch_version") {
            if (!is_one_liner) skip_fn = 1
            next
        }
        if (!(fn in fn_seen)) {
            fn_seen[fn] = 1
            fn_order[++fn_count] = fn
            fn_body[fn] = $0
            if (!is_one_liner) {
                cur_fn = fn
                in_fn = 1
            }
            next
        }
    }
    skip_fn {
        if ($0 ~ /^\}[[:space:]]*$/) skip_fn = 0
        next
    }
    in_fn {
        fn_body[cur_fn] = fn_body[cur_fn] "\n" $0
        if ($0 ~ /^\}[[:space:]]*$/) {
            in_fn = 0
            cur_fn = ""
        }
    }
    END {
        # Emit preserved module state variables
        for (s = 1; s <= state_count; s++) {
            print state_lines[s]
        }
        if (state_count > 0) print ""

        # --- Phase 2: Find root functions called directly in user_code ---
        rest = user_code
        while (match(rest, /[a-zA-Z0-9_:]+/)) {
            tok = substr(rest, RSTART, RLENGTH)
            if ((tok in fn_seen) && !(tok in needed)) {
                needed[tok] = 1
                queue[++q_tail] = tok
            }
            rest = substr(rest, RSTART + RLENGTH)
        }

        # --- Phase 3: Compute transitive closure of reachable functions ---
        if (full_mode == 1) {
            for (i = 1; i <= fn_count; i++) {
                needed[fn_order[i]] = 1
            }
        } else {
            # Build caller -> callee edges across all defined functions
            for (i = 1; i <= fn_count; i++) {
                f = fn_order[i]
                rest = fn_body[f]
                while (match(rest, /[a-zA-Z0-9_:]+/)) {
                    callee = substr(rest, RSTART, RLENGTH)
                    if ((callee in fn_seen) && callee != f) {
                        calls[f, callee] = 1
                    }
                    rest = substr(rest, RSTART + RLENGTH)
                }
            }
            # BFS traversal from root functions
            q_head = 1
            while (q_head <= q_tail) {
                curr = queue[q_head++]
                for (i = 1; i <= fn_count; i++) {
                    cand = fn_order[i]
                    if (!(cand in needed) && ((curr, cand) in calls)) {
                        needed[cand] = 1
                        queue[++q_tail] = cand
                    }
                }
            }
        }

        # Emit only reachable functions in their original definition order
        for (i = 1; i <= fn_count; i++) {
            f = fn_order[i]
            if (f in needed) {
                print fn_body[f] "\n"
            }
        }
    }
    ' "$@"
}

# Generate INSTALL.md instructions inside a bundle directory
function _mbf_export_write_install_md() {
    local bundle_dir="$1" script_name="$2" sys_pkgs="$3" has_node="$4" has_python="$5" has_ai="$6" assets="$7"
    local instr_file="${bundle_dir}/INSTALL.md"

    {
        printf '# Installation & Execution Instructions — `%s`\n\n' "$script_name"
        printf 'Exported by **mbf (Micro Bash Framework)**.\n\n'

        if [ -n "$assets" ]; then
            printf '## Bundled Files\n\n* `%s`\n' "$script_name"
            local item
            for item in $assets; do
                printf '* `%s`\n' "$item"
            done
            printf '\n'
        fi

        printf '## Prerequisites & Setup\n\n'
        if [ -n "$sys_pkgs" ]; then
            printf '### System Packages\n\n```bash\n'
            printf '# Debian / Ubuntu:\nsudo apt-get update && sudo apt-get install -y %s\n\n' "$sys_pkgs"
            printf '# RHEL / Fedora:\nsudo dnf install -y %s\n\n' "$sys_pkgs"
            printf '# macOS:\nbrew install %s\n```\n\n' "$sys_pkgs"
        fi
        if [ "$has_node" -eq 1 ]; then
            printf '### Node.js Runtime\n\n```bash\nnode -v && npm -v\n'
            [ -f "${bundle_dir}/package.json" ] && printf 'npm install\n'
            printf '```\n\n'
        fi
        if [ "$has_python" -eq 1 ]; then
            printf '### Python Runtime\n\n```bash\npython3 --version\n'
            [ -f "${bundle_dir}/requirements.txt" ] && printf 'python3 -m pip install -r requirements.txt\n'
            printf '```\n\n'
        fi
        if [ "$has_ai" -eq 1 ]; then
            printf '### AI CLI Integration\n\nEnsure at least one supported AI CLI (`claude`, `agy`, `gemini`, `codex`) is in `PATH`, or export `OPENAI_API_KEY` / `GEMINI_API_KEY` / `ANTHROPIC_API_KEY`.\n\n'
        fi
        printf '## Running the Script\n\n```bash\nchmod +x ./%s\n./%s\n```\n' "$script_name" "$script_name"
    } > "$instr_file"
}

# Copy any built-in MBF templates referenced in the exported script into `<bundle_dir>/templates/`
# (never overwriting custom project overrides already copied from `<script_dir>/templates/`).
function _mbf_export_copy_builtin_templates() {
    local bundle_dir="$1"
    local exported_script="$2"
    local builtin_root="${MBF_HOME}/lib/templates"
    [ -d "$builtin_root" ] && [ -f "$exported_script" ] || return 1

    local copied=0 tpl_ref
    while IFS= read -r tpl_ref; do
        [ -n "$tpl_ref" ] || continue
        if [ -f "${builtin_root}/${tpl_ref}" ] && [ ! -f "${bundle_dir}/templates/${tpl_ref}" ]; then
            mkdir -p "$(dirname "${bundle_dir}/templates/${tpl_ref}")"
            cp "${builtin_root}/${tpl_ref}" "${bundle_dir}/templates/${tpl_ref}"
            copied=1
        fi
    done < <(grep -oE '[a-zA-Z0-9_./-]+\.tpl' "$exported_script" 2>/dev/null | LC_ALL=C sort -u || true)
    [ "$copied" -eq 1 ]
}

# Copy detected assets and custom templates into `<bundle_dir>` and write `INSTALL.md`
function _mbf_export_copy_bundle_assets() {
    local bundle_dir="$1" script_dir="$2" out_name="$3" sys_pkgs="$4" has_node="$5" has_python="$6" has_ai="$7"
    shift 7
    local copied_assets="" asset has_tpls=0
    declare -A seen_assets=()

    for asset in "$@"; do
        [ -z "$asset" ] && continue
        if [ -z "${seen_assets[$asset]:-}" ] && [ -f "${script_dir}/${asset}" ]; then
            seen_assets["$asset"]=1
            mkdir -p "$(dirname "${bundle_dir}/${asset}")"
            cp "${script_dir}/${asset}" "${bundle_dir}/${asset}"
            copied_assets="${copied_assets} ${asset}"
        fi
    done

    if [ -d "${script_dir}/templates" ]; then
        mkdir -p "${bundle_dir}/templates"
        cp -R "${script_dir}/templates/." "${bundle_dir}/templates/" 2>/dev/null || true
        has_tpls=1
    fi

    if _mbf_export_copy_builtin_templates "$bundle_dir" "${bundle_dir}/${out_name}"; then
        has_tpls=1
    fi
    [ "$has_tpls" -eq 1 ] && copied_assets="${copied_assets} templates/"

    _mbf_export_write_install_md "$bundle_dir" "$out_name" "$sys_pkgs" "$has_node" "$has_python" "$has_ai" "${copied_assets# }"
}

# Scan input script (and any locally sourced helper scripts recursively) to populate
# `_EXP_MODS`, `_EXP_ASSETS`, `_EXP_SYS_PKGS`, `_EXP_BODY`, `_EXP_SHEBANG`, and `_EXP_HAS_{NODE,PYTHON,AI}`.
function _mbf_export_scan_script() {
    local input_script="$1"
    local script_dir="$2"
    local is_root="${3:-1}"
    local line_num=0 raw_line

    local canon_path
    canon_path="$(cd "$(dirname "$input_script")" && pwd)/$(basename "$input_script")"
    if [ -n "${_EXP_SEEN_SRCS[$canon_path]:-}" ]; then
        return 0
    fi
    _EXP_SEEN_SRCS["$canon_path"]=1

    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        raw_line="${raw_line%$'\r'}"
        line_num=$((line_num + 1))

        if [ "$line_num" -eq 1 ] && [[ "$raw_line" == "#!"* ]]; then
            [ "$is_root" -eq 1 ] && _EXP_SHEBANG="$raw_line"
            continue
        fi

        if [[ "$raw_line" =~ ^[[:space:]]*mbf::check_update([[:space:]]|$) ]]; then
            continue
        fi

        if [[ "$raw_line" =~ ^[[:space:]]*mbf::use[[:space:]]+(.+)$ ]]; then
            local mods="${BASH_REMATCH[1]%%#*}" m
            for m in $mods; do
                m="${m//[\"\']/}"
                _EXP_MODS+=("$m")
                [ "$m" == "ai" ] && _EXP_HAS_AI=1
            done
            continue
        fi

        if [[ "$raw_line" =~ ^[[:space:]]*(source|\.)[[:space:]]+(.+)$ ]]; then
            local src_target
            src_target="$(printf '%s' "${BASH_REMATCH[2]%%#*}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            if [[ "$src_target" == *"mbf --init"* ]] || [[ "$src_target" == *"mbf init"* ]] || [[ "$src_target" == *"framework.sh"* ]]; then
                continue
            fi
            local local_src
            if local_src="$(_mbf_export_resolve_local_source "$src_target" "$script_dir")"; then
                local nested_dir
                nested_dir="$(cd "$(dirname "$local_src")" && pwd)"
                _mbf_export_scan_script "$local_src" "$nested_dir" 0
                continue
            fi
        fi

        [[ "$raw_line" =~ mbf::ai:: ]] && _EXP_HAS_AI=1
        [[ "$raw_line" =~ (^|[^a-zA-Z0-9_:])mbf::init([[:space:]]|$|\;) ]] && _EXP_MODS+=("exec")

        if [[ "$raw_line" =~ MBF_BUNDLE_FILES=[\"\']([^\"\']+)[\"\'] ]]; then
            local bf
            for bf in ${BASH_REMATCH[1]}; do
                _EXP_ASSETS+=("$bf")
                [[ "$bf" == *.js ]] && _EXP_HAS_NODE=1
                [[ "$bf" == *.py ]] && _EXP_HAS_PYTHON=1
            done
        fi

        if [[ "$raw_line" =~ MBF_REQUIREMENTS=[\"\']([^\"\']+)[\"\'] ]]; then
            _EXP_SYS_PKGS="${_EXP_SYS_PKGS} ${BASH_REMATCH[1]}"
        fi

        _EXP_BODY="${_EXP_BODY}${raw_line}"$'\n'
    done < "$input_script"
}

# Write the final standalone script file
function _mbf_export_emit_standalone() {
    local output_script="$1" shebang="$2" base_name="$3" shaken_code="$4" body="$5"
    mkdir -p "$(dirname "$output_script")"
    {
        printf '%s\n' "$shebang"
        printf '# ==============================================================================\n'
        printf '# Standalone script exported by mbf v%s (Micro Bash Framework)\n' "${MBF_VERSION:-1.0.0}"
        printf '# Source script: %s\n' "$base_name"
        printf '# ==============================================================================\n\n'
        cat <<'EOF'
_mbf_bash_major="${MBF_BASH_MAJOR_OVERRIDE:-${BASH_VERSINFO[0]:-0}}"
_mbf_bash_minor="${MBF_BASH_MINOR_OVERRIDE:-${BASH_VERSINFO[1]:-0}}"
if [ "$_mbf_bash_major" -lt 4 ] || { [ "$_mbf_bash_major" -eq 4 ] && [ "$_mbf_bash_minor" -lt 3 ]; }; then
    printf 'mbf: Bash >= 4.3 is required (current: %s). On macOS run: brew install bash\n' "${BASH_VERSION:-unknown}" >&2
    return 1 2>/dev/null || exit 1
fi
unset _mbf_bash_major _mbf_bash_minor

EOF
        printf '%s\n' 'MBF_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"'
        printf '%s\n\n' 'MBF_TEMPLATE_PATH="${MBF_TEMPLATE_PATH:-${MBF_SCRIPT_DIR}/templates}"'
        printf '%s\n\n' "$shaken_code"
        printf '# --- Begin User Script ---\n'
        printf '%s' "$body"
    } > "$output_script"
    chmod +x "$output_script" 2>/dev/null || true
}

# Main exporter entry point
# Usage: mbf::exporter::run <input.sh> [-o output.sh] [-d|--bundle-dir dir] [--full-module]
function mbf::exporter::run() {
    local input_script="" output_script="" bundle_dir="" full_module=0

    while [ $# -gt 0 ]; do
        case "$1" in
            -o|--output)      output_script="$2"; shift 2 ;;
            -d|--bundle-dir)  bundle_dir="$2"; shift 2 ;;
            --full-module)    full_module=1; shift 1 ;;
            *)
                if [ -z "$input_script" ]; then
                    input_script="$1"
                elif [ -z "$output_script" ]; then
                    output_script="$1"
                fi
                shift 1
                ;;
        esac
    done

    if [ -z "$input_script" ] || [ ! -f "$input_script" ]; then
        mbf::log::error "Export error: input script '${input_script:-}' not found"
        return 1
    fi

    local script_dir base_name
    script_dir="$(cd "$(dirname "$input_script")" && pwd)"
    base_name="$(basename "$input_script")"

    # 1. Scan script imports, local sources (recursively), and runtime/template assets
    local -a _EXP_MODS=() _EXP_ASSETS=()
    local -A _EXP_SEEN_SRCS=()
    local _EXP_SYS_PKGS="" _EXP_BODY="" _EXP_SHEBANG="#!/usr/bin/env bash"
    local _EXP_HAS_NODE=0 _EXP_HAS_PYTHON=0 _EXP_HAS_AI=0
    _mbf_export_scan_script "$input_script" "$script_dir" 1

    # 2. Resolve all module files (fails if any requested module is missing)
    local mod_list_out
    mod_list_out="$(_mbf_export_collect_modules "$script_dir" ${_EXP_MODS[@]+"${_EXP_MODS[@]}"})" || return 1
    local -a mod_files=()
    local mf
    while IFS= read -r mf; do
        [ -n "$mf" ] && mod_files+=("$mf")
    done <<< "$mod_list_out"

    # 3. Determine output script and optional bundle directory paths
    if [ -z "$bundle_dir" ] && [ "${#_EXP_ASSETS[@]}" -gt 0 ]; then
        if [ -z "$output_script" ]; then
            bundle_dir="bundle_${base_name%.sh}"
        elif [[ "$output_script" != *.sh ]]; then
            bundle_dir="$output_script"
            output_script=""
        fi
    fi
    if [ -n "$bundle_dir" ]; then
        mkdir -p "$bundle_dir"
        output_script="${output_script:-${bundle_dir}/${base_name}}"
    else
        output_script="${output_script:-e_${base_name}}"
    fi

    # 4. Run single-pass POSIX awk tree-shaker and emit standalone script
    local tmp_user_body shaken_code
    tmp_user_body="$(mktemp "${TMPDIR:-/tmp}/mbf.usr.XXXXXX")"
    printf '%s' "$_EXP_BODY" > "$tmp_user_body"
    shaken_code="$(_mbf_export_tree_shake "$full_module" "$tmp_user_body" "${mod_files[@]}" "$tmp_user_body")"
    rm -f "$tmp_user_body"

    _mbf_export_emit_standalone "$output_script" "$_EXP_SHEBANG" "$base_name" "$shaken_code" "$_EXP_BODY"

    # 5. Copy bundle assets, custom templates, and INSTALL.md if bundle_dir is active
    if [ -n "$bundle_dir" ]; then
        _mbf_export_copy_bundle_assets "$bundle_dir" "$script_dir" "$(basename "$output_script")" "${_EXP_SYS_PKGS# }" "$_EXP_HAS_NODE" "$_EXP_HAS_PYTHON" "$_EXP_HAS_AI" ${_EXP_ASSETS[@]+"${_EXP_ASSETS[@]}"}
    fi
    return 0
}
