#!/usr/bin/env bash
# ==============================================================================
# mbf module: exporter
# Smart script bundler with function-level tree-shaking (zero bloatware)
# Supports both single-file standalone export and multi-file directory bundle export
# (including related Node.js scripts, Python scripts, assets, and INSTALL.md)
# ==============================================================================

# Resolve module name to its file path inside MBF_HOME
function _mbf_resolve_module_file() {
    local mod="${1%.sh}"
    case "$mod" in
        parameters)                   mod="args" ;;
        authenication|authentication) mod="auth" ;;
    esac

    if [ -f "${MBF_HOME}/lib/${mod}.sh" ]; then
        printf '%s\n' "${MBF_HOME}/lib/${mod}.sh"
        return 0
    elif [ -f "${MBF_HOME}/${mod}.sh" ]; then
        printf '%s\n' "${MBF_HOME}/${mod}.sh"
        return 0
    fi
    return 1
}

# Extract all function definitions from given bash files wrapped in start/end markers
function _mbf_extract_functions() {
    awk '
    /^[[:space:]]*(function[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*(\(\))?|([a-zA-Z0-9_]+)[[:space:]]*\(\))[[:space:]]*\{/ {
        line = $0
        sub(/^[[:space:]]*function[[:space:]]+/, "", line)
        sub(/[[:space:]]*(\(\))?[[:space:]]*\{.*$/, "", line)
        fn_name = line
        if (!(fn_name in seen)) {
            seen[fn_name] = 1
            in_fn = 1
            print "<<<MBF_FN_START:" fn_name ">>>"
            print $0
            next
        }
    }
    in_fn {
        print $0
        if ($0 ~ /^\}[[:space:]]*$/) {
            in_fn = 0
            print "<<<MBF_FN_END:" fn_name ">>>"
        }
    }
    ' "$@"
}

# Resolve a non-mbf `source` target path relative to the user's script directory
function _mbf_resolve_user_source() {
    local src_target="$1"
    local script_dir="$2"
    local clean_path="${src_target//\"/}"
    clean_path="${clean_path//\'/}"
    clean_path="${clean_path//\$\{DIR\}/$script_dir}"
    clean_path="${clean_path//\$DIR/$script_dir}"

    if [[ "$clean_path" != /* ]] && [ -f "${script_dir}/${clean_path}" ]; then
        clean_path="${script_dir}/${clean_path}"
    fi

    if [ -f "$clean_path" ]; then
        printf '%s\n' "$clean_path"
        return 0
    fi
    return 1
}

# Return 0 if function identifier `fn_name` is referenced as a whole word in `code_text`
function _mbf_is_fn_called_in() {
    local fn_name="$1"
    local code_text="$2"
    printf '%s\n' "$code_text" | grep -Eq "(^|[^a-zA-Z0-9_])${fn_name}([^a-zA-Z0-9_]|$)"
}

# Return 0 if function is an internal loader/init function that should not be exported directly
function _mbf_is_loader_fn() {
    case "$1" in
        init|_import|mbf_use|mbf_is_loaded) return 0 ;;
        *) return 1 ;;
    esac
}

# Generate INSTALL.md instructions inside a bundle directory
function _mbf_write_bundle_instructions() {
    local bundle_dir="$1"
    local script_name="$2"
    local sys_pkgs="$3"
    local has_node="$4"
    local has_python="$5"
    local asset_list="$6"
    local instr_file="${bundle_dir}/INSTALL.md"

    {
        printf '# Installation & Execution Instructions — `%s`\n\n' "$script_name"
        printf 'This bundle was exported by **mbf (Micro Bash Framework)** and contains the standalone script `%s` along with its required runtime programs.\n\n' "$script_name"

        if [ -n "$asset_list" ]; then
            printf '## Bundled Files\n\n'
            printf '* `%s` (Main standalone executable script)\n' "$script_name"
            local item
            for item in $asset_list; do
                printf '* `%s`\n' "$item"
            done
            printf '\n'
        fi

        printf '## Prerequisites & Setup\n\n'

        if [ -n "$sys_pkgs" ]; then
            printf '### 1. System Packages\n\n'
            printf 'Install the required system utilities using your OS package manager:\n\n'
            printf '```bash\n'
            printf '# Debian / Ubuntu:\nsudo apt-get update && sudo apt-get install -y %s\n\n' "$sys_pkgs"
            printf '# RHEL / Fedora / Rocky:\nsudo dnf install -y %s\n\n' "$sys_pkgs"
            printf '# macOS (Homebrew):\nbrew install %s\n' "$sys_pkgs"
            printf '```\n\n'
        fi

        if [ "$has_node" -eq 1 ]; then
            printf '### Node.js Runtime\n\n'
            printf 'Ensure **Node.js** (`node` and `npm`) is installed:\n\n'
            printf '```bash\nnode -v && npm -v\n'
            if [ -f "${bundle_dir}/package.json" ]; then
                printf 'npm install\n'
            fi
            printf '```\n\n'
        fi

        if [ "$has_python" -eq 1 ]; then
            printf '### Python Runtime\n\n'
            printf 'Ensure **Python 3** (`python3` and `pip`) is installed:\n\n'
            printf '```bash\npython3 --version\n'
            if [ -f "${bundle_dir}/requirements.txt" ]; then
                printf 'python3 -m pip install -r requirements.txt\n'
            fi
            printf '```\n\n'
        fi

        printf '## Running the Script\n\n'
        printf '```bash\nchmod +x ./%s\n./%s\n```\n' "$script_name" "$script_name"
    } > "$instr_file"
}

# Export a script using mbf into a standalone bash script or a multi-file bundle directory
# Usage: mbf_export_script <input.sh> [-o output.sh] [-d|--bundle-dir dir] [--full-module]
function mbf_export_script() {
    local input_script=""
    local output_script=""
    local bundle_dir=""
    local full_module=0

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
        print_with_color "Export error: input script '${input_script:-}' not found" "red"
        return 1
    fi

    local script_dir
    script_dir="$(cd "$(dirname "$input_script")" && pwd)"
    local base_script_name
    base_script_name="$(basename "$input_script")"

    # Step 1: Collect candidate module files, detect external assets/programs, and strip mbf imports
    local -a module_files=(
        "${MBF_HOME}/framework.sh"
        "${MBF_HOME}/lib/log.sh"
        "${MBF_HOME}/lib/exec.sh"
        "${MBF_HOME}/lib/check.sh"
    )
    local stripped_body=""
    local shebang="#!/usr/bin/env bash"
    local line_num=0
    local raw_line
    local -a detected_assets=()
    local detected_sys_pkgs=""
    local has_node=0
    local has_python=0

    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        raw_line="${raw_line%$'\r'}"
        line_num=$((line_num + 1))

        if [ "$line_num" -eq 1 ] && [[ "$raw_line" == "#!"* ]]; then
            shebang="$raw_line"
            continue
        fi

        # Handle `mbf_use ...` or `_import ...`
        if [[ "$raw_line" =~ ^[[:space:]]*(mbf_use|_import)[[:space:]]+(.+)$ ]]; then
            local imported_mods="${BASH_REMATCH[2]%%#*}"
            local m resolved
            for m in $imported_mods; do
                m="${m//[\"\']/}"
                if resolved="$(_mbf_resolve_module_file "$m")"; then
                    module_files+=("$resolved")
                fi
            done
            continue
        fi

        # Handle `source ...` or `. ...`
        if [[ "$raw_line" =~ ^[[:space:]]*(source|\.)[[:space:]]+(.+)$ ]]; then
            local src_target
            src_target="$(printf '%s' "${BASH_REMATCH[2]%%#*}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

            if [[ "$src_target" == *"mbf --init"* ]] || [[ "$src_target" == *"mbf init"* ]] || [[ "$src_target" == *"framework.sh"* ]]; then
                continue
            fi

            local base_src
            base_src="$(basename "${src_target//[\"\']/}")"
            local resolved_mod
            if resolved_mod="$(_mbf_resolve_module_file "$base_src")"; then
                module_files+=("$resolved_mod")
                continue
            fi

            local user_src_file
            if user_src_file="$(_mbf_resolve_user_source "$src_target" "$script_dir")"; then
                local inlined_content
                inlined_content="$(grep -v '^#!' "$user_src_file" | tr -d '\r')"
                stripped_body="${stripped_body}${inlined_content}"$'\n'
                continue
            fi
        fi

        # Detect Node.js scripts referenced via runtime_run_node
        if [[ "$raw_line" =~ runtime_run_node[[:space:]]+[\"\']?([^\"\'\;[:space:]]+)[\"\']? ]]; then
            local node_rel="${BASH_REMATCH[1]}"
            node_rel="${node_rel#\$DIR/}"
            node_rel="${node_rel#\$\{DIR\}/}"
            has_node=1
            detected_assets+=("$node_rel")
            if [ -f "${script_dir}/package.json" ]; then
                detected_assets+=("package.json")
            fi
        fi

        # Detect Python scripts referenced via runtime_run_python
        if [[ "$raw_line" =~ runtime_run_python[[:space:]]+[\"\']?([^\"\'\;[:space:]]+)[\"\']? ]]; then
            local py_rel="${BASH_REMATCH[1]}"
            py_rel="${py_rel#\$DIR/}"
            py_rel="${py_rel#\$\{DIR\}/}"
            has_python=1
            detected_assets+=("$py_rel")
            if [ -f "${script_dir}/requirements.txt" ]; then
                detected_assets+=("requirements.txt")
            fi
        fi

        # Detect explicit MBF_BUNDLE_FILES="..."
        if [[ "$raw_line" =~ MBF_BUNDLE_FILES=[\"\']([^\"\']+)[\"\'] ]]; then
            local bf
            for bf in ${BASH_REMATCH[1]}; do
                detected_assets+=("$bf")
            done
        fi

        # Detect system package requirements via runtime_ensure_pkg or MBF_REQUIREMENTS / I7R_REQUIREMENTS
        if [[ "$raw_line" =~ runtime_ensure_pkg[[:space:]]+[\"\']?([a-zA-Z0-9._-]+)[\"\']? ]]; then
            detected_sys_pkgs="${detected_sys_pkgs} ${BASH_REMATCH[1]}"
        fi
        if [[ "$raw_line" =~ (MBF_REQUIREMENTS|I7R_REQUIREMENTS)=[\"\']([^\"\']+)[\"\'] ]]; then
            detected_sys_pkgs="${detected_sys_pkgs} ${BASH_REMATCH[2]}"
        fi

        stripped_body="${stripped_body}${raw_line}"$'\n'
    done < "$input_script"

    # Determine output path (bundle directory vs standalone file)
    if [ -z "$bundle_dir" ] && [ "${#detected_assets[@]}" -gt 0 ]; then
        if [ -z "$output_script" ]; then
            bundle_dir="bundle_${base_script_name%.sh}"
        elif [[ "$output_script" != *.sh ]]; then
            bundle_dir="$output_script"
            output_script=""
        fi
    fi

    if [ -n "$bundle_dir" ]; then
        mkdir -p "$bundle_dir"
        output_script="${output_script:-${bundle_dir}/${base_script_name}}"
    else
        output_script="${output_script:-e_${base_script_name}}"
    fi

    # Step 2: Parse function definitions from collected module files
    local extracted_blob
    extracted_blob="$(_mbf_extract_functions "${module_files[@]}")"

    local -a all_fn_names=()
    declare -A fn_bodies=()
    local current_fn=""
    local current_body=""
    local eline

    while IFS= read -r eline; do
        if [[ "$eline" =~ ^\<\<\<MBF_FN_START:([a-zA-Z0-9_]+)\>\>\>$ ]]; then
            current_fn="${BASH_REMATCH[1]}"
            current_body=""
        elif [[ "$eline" =~ ^\<\<\<MBF_FN_END:([a-zA-Z0-9_]+)\>\>\>$ ]]; then
            if [ -n "$current_fn" ]; then
                all_fn_names+=("$current_fn")
                fn_bodies["$current_fn"]="$current_body"
            fi
            current_fn=""
        elif [ -n "$current_fn" ]; then
            current_body="${current_body}${eline}"$'\n'
        fi
    done <<< "$extracted_blob"

    # Step 3: Tree-Shake — find directly used functions and resolve transitive dependencies
    declare -A needed_fns=()
    local fn

    for fn in "${all_fn_names[@]}"; do
        _mbf_is_loader_fn "$fn" && continue
        if [ "$full_module" -eq 1 ] || _mbf_is_fn_called_in "$fn" "$stripped_body"; then
            needed_fns["$fn"]=1
        fi
    done

    if printf '%s\n' "$stripped_body" | grep -Eq 'SUDO_REQUIRED=["'\'']?1["'\'']?'; then
        needed_fns["initialize_sudo"]=1
    fi

    if [ "$full_module" -eq 0 ]; then
        local changed=1
        while [ "$changed" -eq 1 ]; do
            changed=0
            for fn in "${!needed_fns[@]}"; do
                local body="${fn_bodies[$fn]:-}"
                local dep_fn
                for dep_fn in "${all_fn_names[@]}"; do
                    _mbf_is_loader_fn "$dep_fn" && continue
                    if [ -z "${needed_fns[$dep_fn]:-}" ] && _mbf_is_fn_called_in "$dep_fn" "$body"; then
                        needed_fns["$dep_fn"]=1
                        changed=1
                    fi
                done
            done
        done
    fi

    # Step 4: Write standalone script
    mkdir -p "$(dirname "$output_script")"
    {
        printf '%s\n' "$shebang"
        printf '# ==============================================================================\n'
        printf '# Standalone script exported by mbf (Micro Bash Framework)\n'
        printf '# Source script: %s\n' "$base_script_name"
        printf '# ==============================================================================\n\n'
        printf '%s\n' 'DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"'
        printf '%s\n' 'PRINTF="${PRINTF:-$(command -v printf)}"'
        printf '%s\n' 'SED="${SED:-$(command -v sed)}"'
        printf '%s\n\n' 'MBF_LOG_FILE="${MBF_LOG_FILE:-/tmp/mbf.log}"'

        for fn in "${all_fn_names[@]}"; do
            if [ -n "${needed_fns[$fn]:-}" ]; then
                printf '%s\n' "${fn_bodies[$fn]}"
            fi
        done

        if [ -n "${needed_fns[initialize_sudo]:-}" ]; then
            printf 'if [ "${SUDO_REQUIRED:-0}" == "1" ]; then initialize_sudo; fi\n\n'
        fi

        printf '# --- Begin User Script ---\n'
        printf '%s' "$stripped_body"
    } > "$output_script"

    chmod +x "$output_script" 2>/dev/null || true

    # Step 5: If exporting a bundle directory, copy related assets and generate INSTALL.md
    if [ -n "$bundle_dir" ]; then
        local copied_assets=""
        declare -A seen_assets=()
        local asset
        for asset in "${detected_assets[@]}"; do
            [ -z "$asset" ] && continue
            if [ -z "${seen_assets[$asset]:-}" ] && [ -f "${script_dir}/${asset}" ]; then
                seen_assets["$asset"]=1
                local dest_asset="${bundle_dir}/${asset}"
                mkdir -p "$(dirname "$dest_asset")"
                cp "${script_dir}/${asset}" "$dest_asset"
                copied_assets="${copied_assets} ${asset}"
            fi
        done

        _mbf_write_bundle_instructions \
            "$bundle_dir" \
            "$(basename "$output_script")" \
            "${detected_sys_pkgs# }" \
            "$has_node" \
            "$has_python" \
            "${copied_assets# }"
    fi

    return 0
}

# Backward-compatible process_inline wrapper (outputs m_<basename>)
function process_inline() {
    local file="$1"
    local merged_file="m_$(basename "$file")"
    mbf_export_script "$file" -o "$merged_file"
}
