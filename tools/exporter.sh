#!/usr/bin/env bash
# ==============================================================================
# mbf build tool: exporter
# Fast single-pass awk tree-shaking bundler for standalone scripts & app bundles
# ==============================================================================

# Resolve module or plugin name to its file path in lib/ or plugins/
function _mbf_export_find_module() {
    local name="${1%.sh}"
    if [ -f "${MBF_HOME}/lib/${name}.sh" ]; then
        printf '%s\n' "${MBF_HOME}/lib/${name}.sh"
        return 0
    elif [ -f "${MBF_HOME}/plugins/${name}.sh" ]; then
        printf '%s\n' "${MBF_HOME}/plugins/${name}.sh"
        return 0
    fi
    return 1
}

# Recursively expand module list with `# mbf:requires` headers
function _mbf_export_collect_modules() {
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
        if mod_file="$(_mbf_export_find_module "$mod")"; then
            if [ -z "${seen[$mod_file]:-}" ]; then
                seen["$mod_file"]=1
                reqs="$(grep -m1 '^# mbf:requires ' "$mod_file" 2>/dev/null | sed 's/^# mbf:requires //')"
                for req in $reqs; do
                    queue+=("${req%$'\r'}")
                done
                result+=("$mod_file")
            fi
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

# Single-pass awk tree-shaker:
# Reads module files followed by sentinel `___MBF_USER_SCRIPT___` and user script file.
# Extracts `# mbf:state_start ... # mbf:state_end` blocks and all functions, builds
# call graph in memory, computes transitive closure from user script, and emits state + needed functions.
function _mbf_export_tree_shake() {
    local full_module="$1"
    local user_file="$2"
    shift 2
    awk -v full_mode="$full_module" -v user_file="$user_file" '
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
        if ($0 !~ /^MBF_HOME=/ && $0 !~ /^MBF_LOADED_MODULES=/) {
            state_lines[++state_count] = $0
        }
        next
    }
    /^[[:space:]]*function[[:space:]]+[a-zA-Z0-9_:]+[[:space:]]*(\(\))?[[:space:]]*\{/ {
        line = $0
        sub(/^[[:space:]]*function[[:space:]]+/, "", line)
        sub(/[[:space:]]*(\(\))?[[:space:]]*\{.*$/, "", line)
        fn = line
        if (fn == "mbf::use" || fn == "mbf::is_loaded" || fn == "_mbf_resolve_path") {
            skip_fn = 1
            next
        }
        if (!(fn in fn_seen)) {
            fn_seen[fn] = 1
            fn_order[++fn_count] = fn
            cur_fn = fn
            fn_body[cur_fn] = $0
            in_fn = 1
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
        for (s = 1; s <= state_count; s++) {
            print state_lines[s]
        }
        if (state_count > 0) print ""

        # Tokenize user_code and each function body into words (including `:` for mbf::* names)
        n_u = patsplit(user_code, u_tokens, /[a-zA-Z0-9_:]+/)
        for (i = 1; i <= n_u; i++) {
            tok = u_tokens[i]
            if (tok in fn_seen) {
                needed[tok] = 1
                queue[++q_tail] = tok
            }
        }

        if (full_mode == 1) {
            for (i = 1; i <= fn_count; i++) {
                needed[fn_order[i]] = 1
            }
        } else {
            # Pre-tokenize each function body once and run BFS
            for (i = 1; i <= fn_count; i++) {
                f = fn_order[i]
                n_b = patsplit(fn_body[f], b_tokens, /[a-zA-Z0-9_:]+/)
                for (j = 1; j <= n_b; j++) {
                    callee = b_tokens[j]
                    if (callee in fn_seen && callee != f) {
                        calls[f, callee] = 1
                    }
                }
            }
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
    local bundle_dir="$1" script_name="$2" sys_pkgs="$3" has_node="$4" has_python="$5" assets="$6"
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
        printf '## Running the Script\n\n```bash\nchmod +x ./%s\n./%s\n```\n' "$script_name" "$script_name"
    } > "$instr_file"
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

    # Stage 1: Parse script imports, inline local user sources, and detect bundle assets
    local -a requested_mods=()
    local -a detected_assets=()
    local detected_sys_pkgs="" stripped_body="" shebang="#!/usr/bin/env bash"
    local line_num=0 raw_line has_node=0 has_python=0

    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        raw_line="${raw_line%$'\r'}"
        line_num=$((line_num + 1))

        if [ "$line_num" -eq 1 ] && [[ "$raw_line" == "#!"* ]]; then
            shebang="$raw_line"
            continue
        fi

        if [[ "$raw_line" =~ ^[[:space:]]*mbf::use[[:space:]]+(.+)$ ]]; then
            local mods="${BASH_REMATCH[1]%%#*}" m
            for m in $mods; do
                requested_mods+=("${m//[\"\']/}")
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
                stripped_body="${stripped_body}$(grep -v '^#!' "$local_src" | tr -d '\r')"$'\n'
                continue
            fi
        fi

        if [[ "$raw_line" =~ mbf::runtime::run_node[[:space:]]+[\"\']?([^\"\'\;[:space:]]+)[\"\']? ]]; then
            local n_rel="${BASH_REMATCH[1]#\$DIR/}"
            n_rel="${n_rel#\$\{DIR\}/}"
            has_node=1
            detected_assets+=("$n_rel")
            [ -f "${script_dir}/package.json" ] && detected_assets+=("package.json")
        fi

        if [[ "$raw_line" =~ mbf::runtime::run_python[[:space:]]+[\"\']?([^\"\'\;[:space:]]+)[\"\']? ]]; then
            local p_rel="${BASH_REMATCH[1]#\$DIR/}"
            p_rel="${p_rel#\$\{DIR\}/}"
            has_python=1
            detected_assets+=("$p_rel")
            [ -f "${script_dir}/requirements.txt" ] && detected_assets+=("requirements.txt")
        fi

        if [[ "$raw_line" =~ MBF_BUNDLE_FILES=[\"\']([^\"\']+)[\"\'] ]]; then
            local bf
            for bf in ${BASH_REMATCH[1]}; do
                detected_assets+=("$bf")
            done
        fi

        if [[ "$raw_line" =~ mbf::runtime::ensure_pkg[[:space:]]+[\"\']?([a-zA-Z0-9._-]+)[\"\']? ]]; then
            detected_sys_pkgs="${detected_sys_pkgs} ${BASH_REMATCH[1]}"
        fi
        if [[ "$raw_line" =~ MBF_REQUIREMENTS=[\"\']([^\"\']+)[\"\'] ]]; then
            detected_sys_pkgs="${detected_sys_pkgs} ${BASH_REMATCH[1]}"
        fi

        stripped_body="${stripped_body}${raw_line}"$'\n'
    done < "$input_script"

    # Determine output path
    if [ -z "$bundle_dir" ] && [ "${#detected_assets[@]}" -gt 0 ]; then
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

    # Stage 2: Resolve all module files (including transitive `# mbf:requires`)
    local -a mod_files=()
    local mf
    while IFS= read -r mf; do
        [ -n "$mf" ] && mod_files+=("$mf")
    done < <(_mbf_export_collect_modules "${requested_mods[@]}")

    # Stage 3: Single-pass awk tree-shaking
    local tmp_user_body
    tmp_user_body="$(mktemp "${TMPDIR:-/tmp}/mbf.usr.XXXXXX")"
    printf '%s' "$stripped_body" > "$tmp_user_body"

    local shaken_code
    shaken_code="$(_mbf_export_tree_shake "$full_module" "$tmp_user_body" "${mod_files[@]}" "$tmp_user_body")"
    rm -f "$tmp_user_body"

    # Stage 4: Emit standalone script
    mkdir -p "$(dirname "$output_script")"
    {
        printf '%s\n' "$shebang"
        printf '# ==============================================================================\n'
        printf '# Standalone script exported by mbf (Micro Bash Framework)\n'
        printf '# Source script: %s\n' "$base_name"
        printf '# ==============================================================================\n\n'
        printf '%s\n\n' 'MBF_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"'
        printf '%s\n\n' "$shaken_code"
        printf '# --- Begin User Script ---\n'
        printf '%s' "$stripped_body"
    } > "$output_script"
    chmod +x "$output_script" 2>/dev/null || true

    # Stage 5: Bundle assets + INSTALL.md if bundle_dir is active
    if [ -n "$bundle_dir" ]; then
        local copied_assets="" asset
        declare -A seen_assets=()
        for asset in "${detected_assets[@]}"; do
            [ -z "$asset" ] && continue
            if [ -z "${seen_assets[$asset]:-}" ] && [ -f "${script_dir}/${asset}" ]; then
                seen_assets["$asset"]=1
                mkdir -p "$(dirname "${bundle_dir}/${asset}")"
                cp "${script_dir}/${asset}" "${bundle_dir}/${asset}"
                copied_assets="${copied_assets} ${asset}"
            fi
        done
        _mbf_export_write_install_md "$bundle_dir" "$(basename "$output_script")" "${detected_sys_pkgs# }" "$has_node" "$has_python" "${copied_assets# }"
    fi
    return 0
}
