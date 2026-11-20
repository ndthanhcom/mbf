#!/usr/bin/env bash
# ==============================================================================
# mbf tool: plugin
# Manifest-driven plugin & extended-script repository manager
#
# Tracks installed plugin packages in `${MBF_USER_DATA_DIR}/.installed_plugins`,
# parses `README.md` manifest tables (mandatory + optional rows), enforces MBF
# semver range compatibility (`mbf-compat`), and supports `github.com/<owner>/<repo>`
# shorthand URLs.
# ==============================================================================

function _mbf_plugin_data_dir() {
    printf '%s\n' "${MBF_USER_DATA_DIR:-${XDG_DATA_HOME:-${HOME:-/tmp}/.local/share}/mbf}"
}

function _mbf_plugin_plugins_dir() {
    local d
    d="$(_mbf_plugin_data_dir)"
    printf '%s\n' "${MBF_USER_PLUGINS_DIR:-${d}/plugins}"
}

function _mbf_plugin_registry_file() {
    local d
    d="$(_mbf_plugin_data_dir)"
    printf '%s/.installed_plugins\n' "$d"
}

# Normalize plugin source:
#   - Local file or directory -> absolute path
#   - `github.com/<owner>/<repo>` -> `https://github.com/<owner>/<repo>.git`
#   - Full git/https/ssh URLs -> preserved as-is
function _mbf_plugin_normalize_source() {
    local raw="$1"
    if [ -d "$raw" ]; then
        (cd "$raw" && pwd)
        return 0
    elif [ -f "$raw" ]; then
        local dir base
        dir="$(cd "$(dirname "$raw")" && pwd)"
        base="$(basename "$raw")"
        printf '%s/%s\n' "$dir" "$base"
        return 0
    fi

    local clean="${raw%/}"
    if [[ "$clean" == github.com/* ]]; then
        clean="${clean%.git}"
        printf 'https://%s.git\n' "$clean"
        return 0
    fi
    printf '%s\n' "$clean"
}

# Return 0 if semantic version `$1` satisfies all constraints in `$2`
# Supports: `>=1.0.0 <=1.2.9`, `v1.0.0 - v1.2.9`, `1.0.0..1.2.9`, `>=1.0.0`, `<2.0.0`, `==1.0.0`, `1.0.0`
function _mbf_plugin_check_compat() {
    local cur="${1#v}"
    local expr="${2:-}"
    [ -z "$expr" ] || [ "$expr" == "*" ] && return 0

    # Normalize `v1.0.0 - v1.2.9` or `1.0.0..1.2.9` into `>=1.0.0 <=1.2.9`
    if [[ "$expr" =~ ^[[:space:]]*v?([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*(-|\.\.)[[:space:]]*v?([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*$ ]]; then
        expr=">=${BASH_REMATCH[1]} <=${BASH_REMATCH[3]}"
    fi

    local tok op ver
    for tok in $expr; do
        if [[ "$tok" == ">="* ]]; then
            op=">="; ver="${tok#>=}"
        elif [[ "$tok" == "<="* ]]; then
            op="<="; ver="${tok#<=}"
        elif [[ "$tok" == "=="* ]]; then
            op="=="; ver="${tok#==}"
        elif [[ "$tok" == ">"* ]]; then
            op=">"; ver="${tok#>}"
        elif [[ "$tok" == "<"* ]]; then
            op="<"; ver="${tok#<}"
        elif [[ "$tok" == "="* ]]; then
            op="=="; ver="${tok#=}"
        else
            op="=="; ver="$tok"
        fi
        ver="${ver#v}"

        case "$op" in
            ">=")
                [ "$cur" == "$ver" ] || _mbf_version_gt "$cur" "$ver" || return 1
                ;;
            "<=")
                [ "$cur" == "$ver" ] || _mbf_version_gt "$ver" "$cur" || return 1
                ;;
            ">")
                _mbf_version_gt "$cur" "$ver" || return 1
                ;;
            "<")
                _mbf_version_gt "$ver" "$cur" || return 1
                ;;
            "==")
                [ "$cur" == "$ver" ] || return 1
                ;;
        esac
    done
    return 0
}

# Parse the Markdown manifest table from `<readme_file>` into `key=value` lines.
# Prefers `<!-- mbf:manifest:start --> ... <!-- mbf:manifest:end -->`; falls back
# to the first `| Field | Value |` Markdown table in the file.
function _mbf_plugin_parse_manifest() {
    local readme="$1"
    [ -r "$readme" ] || return 1

    awk '
        function trim(s) {
            sub(/^[ \t\r]+/, "", s)
            sub(/[ \t\r]+$/, "", s)
            return s
        }
        function clean(s) {
            s = trim(s)
            gsub(/\*\*/, "", s)
            gsub(/`/, "", s)
            return trim(s)
        }
        /<!-- *mbf:manifest:start *-->/ { has_markers = 1; in_block = 1; next }
        /<!-- *mbf:manifest:end *-->/   { in_block = 0; exit }
        {
            lines[++n] = $0
            if (in_block) {
                block[++bn] = $0
            }
        }
        END {
            if (has_markers) {
                for (i = 1; i <= bn; i++) {
                    line = block[i]
                    if (line !~ /^\|/) continue
                    cnt = split(line, cols, "|")
                    if (cnt < 3) continue
                    k = tolower(clean(cols[2]))
                    v = clean(cols[3])
                    if (k == "" || k == "field" || k ~ /^-+$/) continue
                    if (v == "-" || v == "none" || v == "(none)") v = ""
                    print k "=" v
                }
            } else {
                in_tbl = 0
                for (i = 1; i <= n; i++) {
                    line = lines[i]
                    if (line ~ /^\|/) {
                        in_tbl = 1
                        cnt = split(line, cols, "|")
                        if (cnt < 3) continue
                        k = tolower(clean(cols[2]))
                        v = clean(cols[3])
                        if (k == "" || k == "field" || k ~ /^-+$/) continue
                        if (v == "-" || v == "none" || v == "(none)") v = ""
                        print k "=" v
                    } else if (in_tbl) {
                        break
                    }
                }
            }
        }
    ' "$readme"
}

# Write or update a single package entry in `.installed_plugins`
function _mbf_plugin_registry_set() {
    local reg_file="$1" name="$2" ver="$3" src="$4" compat="$5" plugins_csv="$6" tpls_csv="$7" scripts_csv="$8"
    local ts
    ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    mkdir -p "$(dirname "$reg_file")"

    local existing=""
    if [ -f "$reg_file" ]; then
        existing="$(MBF_N="$name" awk -F'|' '$0 ~ /^#/ || $1 != ENVIRON["MBF_N"] { print }' "$reg_file")"
    fi
    {
        if [ -n "$existing" ]; then
            printf '%s\n' "$existing"
        else
            printf '# name|version|source|mbf_compat|plugins|templates|scripts|installed_at\n'
        fi
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$name" "$ver" "$src" "$compat" "$plugins_csv" "$tpls_csv" "$scripts_csv" "$ts"
    } > "${reg_file}.tmp.$$" && mv -f "${reg_file}.tmp.$$" "$reg_file"
}

# Remove a package entry from `.installed_plugins`
function _mbf_plugin_registry_del() {
    local reg_file="$1" name="$2"
    [ -f "$reg_file" ] || return 0
    MBF_N="$name" awk -F'|' '$0 ~ /^#/ || $1 != ENVIRON["MBF_N"] { print }' "$reg_file" > "${reg_file}.tmp.$$" \
        && mv -f "${reg_file}.tmp.$$" "$reg_file"
}

# Install plugins, templates, and scripts from a local directory `<repo_dir>` using its `README.md` manifest
function _mbf_plugin_install_from_dir() {
    local repo_dir="$1"
    local orig_source="$2"
    local force="${3:-0}"
    local readme="${repo_dir}/README.md"

    local p_name="" p_ver="" p_compat="" p_api="1" p_plugins="" p_tpls="" p_scripts="" p_reqs="" p_sysdeps=""
    if [ -r "$readme" ]; then
        local kv k v
        while IFS= read -r kv; do
            [ -n "$kv" ] || continue
            k="${kv%%=*}"
            v="${kv#*=}"
            case "$k" in
                name)        p_name="$v" ;;
                version)     p_ver="$v" ;;
                mbf-compat)  p_compat="$v" ;;
                mbf-api)     p_api="$v" ;;
                plugins)     p_plugins="$v" ;;
                templates)   p_tpls="$v" ;;
                scripts)     p_scripts="$v" ;;
                requires)    p_reqs="$v" ;;
                system-deps) p_sysdeps="$v" ;;
            esac
        done < <(_mbf_plugin_parse_manifest "$readme")
    else
        mbf::log::error "Plugin repository is missing README.md manifest: $repo_dir"
        return 1
    fi

    # Validate mandatory manifest rows
    local missing=""
    [ -z "$p_name" ]    && missing="${missing} name"
    [ -z "$p_ver" ]     && missing="${missing} version"
    [ -z "$p_compat" ]  && missing="${missing} mbf-compat"
    [ -z "$p_plugins" ] && [ -z "$p_scripts" ] && missing="${missing} plugins/scripts"
    if [ -n "$missing" ]; then
        mbf::log::error "README.md manifest in '${repo_dir}' is missing mandatory field(s):${missing}"
        return 1
    fi

    # Check MBF semver range compatibility
    if ! _mbf_plugin_check_compat "${MBF_VERSION:-1.0.0}" "$p_compat"; then
        if [ "$force" -eq 1 ]; then
            mbf::log::warn "Forcing install of '${p_name}' despite MBF version mismatch (requires '${p_compat}', current: v${MBF_VERSION:-1.0.0})"
        else
            mbf::log::error "Plugin '${p_name}' (v${p_ver}) requires MBF ${p_compat}, but current MBF is v${MBF_VERSION:-1.0.0}. Run 'mbf version change <tag>' or pass --force."
            return 1
        fi
    fi

    # Check MBF API version
    if [ -n "$p_api" ] && [[ "$p_api" =~ ^[0-9]+$ ]] && [ "$p_api" -gt "${MBF_API_VERSION:-1}" ]; then
        if [ "$force" -eq 0 ]; then
            mbf::log::error "Plugin '${p_name}' requires MBF API v${p_api}, but current MBF supports API v${MBF_API_VERSION:-1}."
            return 1
        fi
    fi

    # Warn on missing optional system-deps
    local dep
    for dep in ${p_sysdeps//,/ }; do
        [ -n "$dep" ] || continue
        if ! command -v "$dep" >/dev/null 2>&1; then
            mbf::log::warn "Plugin '${p_name}' recommends system binary '${dep}' (not found in PATH)"
        fi
    done

    # Check required MBF modules
    local req
    for req in ${p_reqs//,/ }; do
        [ -n "$req" ] || continue
        if ! _mbf_resolve_path "$req" >/dev/null 2>&1; then
            mbf::log::warn "Plugin '${p_name}' declares requires '${req}' (not currently resolved)"
        fi
    done

    local data_dir plugins_dir tpls_dir repos_dir reg_file
    data_dir="$(_mbf_plugin_data_dir)"
    plugins_dir="$(_mbf_plugin_plugins_dir)"
    tpls_dir="${data_dir}/templates"
    repos_dir="${data_dir}/repos"
    reg_file="$(_mbf_plugin_registry_file)"

    mkdir -p "$plugins_dir" "$repos_dir" || return 1

    # Validate & install declared plugin files
    # shellcheck disable=SC1091
    source "${MBF_HOME}/tools/doctor.sh"

    local installed_plugins="" pf src_pf base_pf dst_pf
    for pf in ${p_plugins//,/ }; do
        [ -n "$pf" ] || continue
        src_pf="${repo_dir}/${pf}"
        if [ ! -f "$src_pf" ]; then
            mbf::log::error "Manifest declared plugin '${pf}', but file not found in ${repo_dir}"
            return 1
        fi
        if ! MBF_EXT_PATH="${repo_dir}/plugins:${repo_dir}/lib:${repo_dir}${MBF_EXT_PATH:+:${MBF_EXT_PATH}}" mbf::doctor::run "$src_pf"; then
            return 1
        fi
        base_pf="$(basename "$src_pf")"
        dst_pf="${plugins_dir}/${base_pf}"
        cp "$src_pf" "$dst_pf" || return 1
        installed_plugins="${installed_plugins:+${installed_plugins},}${base_pf}"
    done

    # Install optional templates
    local installed_tpls="" tf src_tf rel_tf
    for tf in ${p_tpls//,/ }; do
        [ -n "$tf" ] || continue
        src_tf="${repo_dir}/${tf%/}"
        if [ -d "$src_tf" ]; then
            mkdir -p "$tpls_dir"
            cp -R "${src_tf}/." "$tpls_dir/" 2>/dev/null || true
            while IFS= read -r -d '' rel_tf; do
                [ -n "$rel_tf" ] || continue
                rel_tf="${rel_tf#"${src_tf}/"}"
                installed_tpls="${installed_tpls:+${installed_tpls},}${rel_tf}"
            done < <(_mbf_find_sorted "$src_tf" -type f)
        elif [ -f "$src_tf" ]; then
            mkdir -p "$tpls_dir"
            cp "$src_tf" "${tpls_dir}/$(basename "$src_tf")"
            installed_tpls="${installed_tpls:+${installed_tpls},}$(basename "$src_tf")"
        fi
    done

    # Verify declared scripts exist and mark executable
    local installed_scripts="" sf
    for sf in ${p_scripts//,/ }; do
        [ -n "$sf" ] || continue
        if [ ! -f "${repo_dir}/${sf}" ]; then
            mbf::log::error "Manifest declared script '${sf}', but file not found in ${repo_dir}"
            return 1
        fi
        chmod +x "${repo_dir}/${sf}" 2>/dev/null || true
        installed_scripts="${installed_scripts:+${installed_scripts},}${sf}"
    done

    # Copy/keep repo directory in `${data_dir}/repos/${p_name}` if not already there
    local target_repo="${repos_dir}/${p_name}"
    if [ "$repo_dir" != "$target_repo" ]; then
        rm -rf "$target_repo"
        cp -R "$repo_dir" "$target_repo"
    fi

    _mbf_plugin_registry_set "$reg_file" "$p_name" "$p_ver" "$orig_source" "$p_compat" \
        "$installed_plugins" "$installed_tpls" "$installed_scripts"

    mbf::log::ok "Installed '${p_name}' v${p_ver} (compat: ${p_compat})${installed_plugins:+ [plugins: ${installed_plugins}]}${installed_scripts:+ [scripts: ${installed_scripts}]}"
    return 0
}

# Install a plugin from a local `.sh` file, local repo directory, or Git/GitHub URL
# Usage: mbf::plugin::add <github.com/owner/repo | url | dir | file.sh> [--ref <tag>] [--force]
function mbf::plugin::add() {
    local raw_src="" ref="" force=0 name_override=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --ref)   ref="$2"; shift 2 ;;
            --force) force=1; shift 1 ;;
            *)
                if [ -z "$raw_src" ]; then
                    raw_src="$1"
                elif [ -z "$name_override" ]; then
                    name_override="$1"
                fi
                shift 1
                ;;
        esac
    done

    if [ -z "$raw_src" ]; then
        mbf::log::error "Usage: mbf plugin add <github.com/owner/repo | git_url | dir | file.sh> [--ref <tag>] [--force]"
        return 1
    fi

    local norm_src
    norm_src="$(_mbf_plugin_normalize_source "$raw_src")"

    # Case 1: Single standalone `.sh` plugin file
    if [ -f "$norm_src" ]; then
        local plugins_dir reg_file dst_name dst
        plugins_dir="$(_mbf_plugin_plugins_dir)"
        reg_file="$(_mbf_plugin_registry_file)"
        mkdir -p "$plugins_dir" || return 1

        dst_name="${name_override:-$(basename "$norm_src" .sh)}"
        dst="${plugins_dir}/${dst_name%.sh}.sh"
        cp "$norm_src" "$dst" || return 1

        # shellcheck disable=SC1091
        source "${MBF_HOME}/tools/doctor.sh"
        if ! mbf::doctor::run "$dst"; then
            rm -f "$dst"
            return 1
        fi
        _mbf_plugin_registry_set "$reg_file" "${dst_name%.sh}" "local" "$norm_src" "*" "${dst_name%.sh}.sh" "" ""
        mbf::log::ok "Installed user plugin '${dst_name%.sh}' -> $dst"
        return 0
    fi

    # Case 2: Local plugin repository directory (with README.md manifest)
    if [ -d "$norm_src" ]; then
        _mbf_plugin_install_from_dir "$norm_src" "$norm_src" "$force"
        return $?
    fi

    # Case 3: Remote Git / GitHub repository
    mbf::use exec
    local tmp_repo
    mbf::exec::tmpdir tmp_repo || return 1
    local -a clone_cmd=(git clone --depth 1)
    [ -n "$ref" ] && clone_cmd+=(--branch "$ref")
    clone_cmd+=("$norm_src" "$tmp_repo")

    mbf::log::info "Cloning plugin repository: $norm_src"
    if ! "${clone_cmd[@]}"; then
        mbf::log::error "Failed to clone plugin repository: $norm_src"
        return 1
    fi

    _mbf_plugin_install_from_dir "$tmp_repo" "$norm_src" "$force"
}

# List tracked installed plugins from `.installed_plugins` and built-in plugins
function mbf::plugin::list() {
    local reg_file plugins_dir
    reg_file="$(_mbf_plugin_registry_file)"
    plugins_dir="$(_mbf_plugin_plugins_dir)"

    printf 'Installed Plugin Packages (%s):\n' "$reg_file"
    if [ -f "$reg_file" ] && grep -qv '^#' "$reg_file"; then
        printf '  %-20s %-9s %-18s %-24s %s\n' "NAME" "VERSION" "MBF-COMPAT" "PLUGINS" "SOURCE"
        # shellcheck disable=SC2034
        local name ver src compat pls tpls scs ts
        while IFS='|' read -r name ver src compat pls tpls scs ts; do
            [[ -z "$name" || "$name" == \#* ]] && continue
            printf '  %-20s %-9s %-18s %-24s %s\n' "$name" "$ver" "$compat" "${pls:-$scs}" "$src"
        done < "$reg_file"
        printf '\n'
    elif [ -d "$plugins_dir" ] && compgen -G "${plugins_dir}/*.sh" >/dev/null 2>&1; then
        printf '  (untracked files in %s)\n\n' "$plugins_dir"
    else
        printf '  (none installed — use: mbf plugin add github.com/<owner>/<repo>)\n\n'
    fi

    if declare -F _mbf_list_dir >/dev/null 2>&1; then
        _mbf_list_dir "Built-in Plugins" "${MBF_HOME}/plugins"
    fi
}

# Update one or all installed plugin packages tracked in `.installed_plugins`
# Usage: mbf::plugin::update [name] [--force]
function mbf::plugin::update() {
    local target_name="" force=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --force) force=1; shift 1 ;;
            *)       [ -z "$target_name" ] && target_name="$1"; shift 1 ;;
        esac
    done

    local reg_file data_dir
    reg_file="$(_mbf_plugin_registry_file)"
    data_dir="$(_mbf_plugin_data_dir)"
    if [ ! -f "$reg_file" ]; then
        mbf::log::warn "No installed plugins found in $reg_file"
        return 0
    fi

    local updated=0 rc=0
    # shellcheck disable=SC2034
    local name ver src compat pls tpls scs ts
    while IFS='|' read -r name ver src compat pls tpls scs ts; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        if [ -n "$target_name" ] && [ "$name" != "$target_name" ]; then
            continue
        fi
        local repo_dir="${data_dir}/repos/${name}"
        if [ -d "${repo_dir}/.git" ]; then
            if ! git -C "$repo_dir" symbolic-ref -q HEAD >/dev/null 2>&1; then
                mbf::log::warn "Plugin '${name}' is pinned to a detached ref; re-run 'mbf plugin add ${src}' to change ref or track default branch."
                updated=$((updated + 1))
                continue
            fi
            mbf::log::info "Updating plugin '${name}' from ${src}..."
            if git -C "$repo_dir" pull --ff-only; then
                _mbf_plugin_install_from_dir "$repo_dir" "$src" "$force" || rc=1
                updated=$((updated + 1))
            else
                mbf::log::error "Failed to git pull plugin '${name}'"
                rc=1
            fi
        elif [ -d "$src" ]; then
            mbf::log::info "Refreshing local plugin '${name}' from ${src}..."
            _mbf_plugin_install_from_dir "$src" "$src" "$force" || rc=1
            updated=$((updated + 1))
        else
            mbf::log::warn "Skipping non-git single-file plugin '${name}' (${src})"
        fi
    done < "$reg_file"

    if [ -n "$target_name" ] && [ "$updated" -eq 0 ]; then
        mbf::log::error "Installed plugin '${target_name}' not found in $reg_file"
        return 1
    fi
    return "$rc"
}

# Remove an installed plugin package (and all its owned plugins, templates, and cloned repo)
# Usage: mbf::plugin::remove <name>
function mbf::plugin::remove() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        mbf::log::error "Usage: mbf plugin remove <plugin_or_package_name>"
        return 1
    fi
    target="${target%.sh}"

    local reg_file data_dir plugins_dir tpls_dir
    reg_file="$(_mbf_plugin_registry_file)"
    data_dir="$(_mbf_plugin_data_dir)"
    plugins_dir="$(_mbf_plugin_plugins_dir)"
    tpls_dir="${data_dir}/templates"

    if [ -f "$reg_file" ]; then
        local row
        row="$(MBF_N="$target" awk -F'|' '$0 !~ /^#/ && $1 == ENVIRON["MBF_N"] { print; exit }' "$reg_file")"
        if [ -n "$row" ]; then
            # shellcheck disable=SC2034
            local name ver src compat pls tpls scs ts
            IFS='|' read -r name ver src compat pls tpls scs ts <<< "$row"

            local pf tf
            for pf in ${pls//,/ }; do
                [ -n "$pf" ] && rm -f "${plugins_dir}/${pf}"
            done
            for tf in ${tpls//,/ }; do
                [ -n "$tf" ] && rm -f "${tpls_dir}/${tf}"
            done
            rm -rf "${data_dir}/repos/${name}"
            _mbf_plugin_registry_del "$reg_file" "$name"
            mbf::log::ok "Removed installed plugin package '${name}'"
            return 0
        fi
    fi

    # Fallback: remove untracked standalone `.sh` file
    if [ -f "${plugins_dir}/${target}.sh" ]; then
        rm -f "${plugins_dir}/${target}.sh"
        mbf::log::ok "Removed user plugin '${target}'"
        return 0
    fi

    mbf::log::error "mbf plugin remove: '${target}' not found in ${reg_file} or ${plugins_dir}"
    return 1
}

# Run an extended script bundled in an installed plugin repository
# Usage: mbf::plugin::run <package_name> <script_name> [args...]
function mbf::plugin::run() {
    local pkg="${1:-}"
    local script="${2:-}"
    shift 2 2>/dev/null || true

    if [ -z "$pkg" ] || [ -z "$script" ]; then
        mbf::log::error "Usage: mbf plugin run <package_name> <script.sh> [args...]"
        return 1
    fi

    local data_dir target_script
    data_dir="$(_mbf_plugin_data_dir)"
    target_script="${data_dir}/repos/${pkg}/${script}"
    if [ ! -f "$target_script" ]; then
        mbf::log::error "Script '${script}' not found in installed package '${pkg}' (${target_script})"
        return 1
    fi
    bash "$target_script" "$@"
}
