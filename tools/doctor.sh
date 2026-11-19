#!/usr/bin/env bash
# ==============================================================================
# mbf build tool: doctor
# Diagnostics & compliance validator for mbf scripts and custom extensions
# ==============================================================================

# Validate an mbf script or custom extension file for compliance and export readiness
# Usage: mbf::doctor::run <script_or_extension.sh>
function mbf::doctor::run() {
    local target="$1"
    if [ -z "$target" ] || [ ! -f "$target" ]; then
        mbf::log::error "mbf::doctor::run: file not found: '${target:-}'"
        return 1
    fi

    mbf::use template
    local script_dir base_name errors=0 warnings=0
    script_dir="$(cd "$(dirname "$target")" && pwd)"
    base_name="$(basename "$target")"
    # shellcheck disable=SC2034
    MBF_SCRIPT_DIR="$script_dir"

    printf '=== MBF Doctor Diagnostics: %s ===\n' "$target"

    # 1. Check if file is a custom extension (`# @mbf-module:`)
    local mod_tag rank_tag api_tag
    mod_tag="$(grep -m1 '^# @mbf-module:' "$target" 2>/dev/null | sed 's/^# @mbf-module:[[:space:]]*//' | tr -d '\r')"
    rank_tag="$(grep -m1 '^# @mbf-rank:' "$target" 2>/dev/null | sed 's/^# @mbf-rank:[[:space:]]*//' | tr -d '\r')"
    api_tag="$(grep -m1 '^# @mbf-api:' "$target" 2>/dev/null | sed 's/^# @mbf-api:[[:space:]]*//' | tr -d '\r')"

    if [ -n "$mod_tag" ]; then
        printf '[INFO] Detected mbf extension module: %s (rank: %s, api: %s)\n' "$mod_tag" "${rank_tag:-unranked}" "${api_tag:-1}"
        if [ -z "$rank_tag" ]; then
            mbf::log::warn "Extension '$base_name' is missing '# @mbf-rank: ••' header"
            warnings=$((warnings + 1))
        fi
        if [ -n "$api_tag" ]; then
            if [[ ! "$api_tag" =~ ^[0-9]+$ ]]; then
                mbf::log::error "Invalid '# @mbf-api: $api_tag' in $base_name (expected integer)"
                errors=$((errors + 1))
            elif [ "$api_tag" -gt "${MBF_API_VERSION:-1}" ]; then
                mbf::log::error "Extension '$base_name' requires MBF API v${api_tag}, but current MBF supports API v${MBF_API_VERSION:-1}"
                errors=$((errors + 1))
            else
                printf '[OK]   # @mbf-api: %s (compatible with MBF API v%s)\n' "$api_tag" "${MBF_API_VERSION:-1}"
            fi
        fi

        # Check `# mbf:requires` dependencies
        local reqs req resolved_req
        reqs="$(grep -m1 '^# mbf:requires ' "$target" 2>/dev/null | sed 's/^# mbf:requires //')"
        for req in $reqs; do
            req="${req%$'\r'}"
            if resolved_req="$(_mbf_resolve_path "$req")"; then
                printf '[OK]   # mbf:requires %-12s -> %s\n' "$req" "$resolved_req"
            else
                mbf::log::error "Unresolved '# mbf:requires $req' in $base_name"
                errors=$((errors + 1))
            fi
        done

        # Check function naming convention (`*::${mod_tag}::*` or `_mbf_${mod_tag}_*`)
        local fn_name
        while IFS= read -r fn_name; do
            [ -z "$fn_name" ] && continue
            if [[ "$fn_name" != *"::${mod_tag}::"* ]] && [[ "$fn_name" != "_mbf_${mod_tag}_"* ]]; then
                mbf::log::error "Function '$fn_name' violates extension naming convention (expected 'mbf::${mod_tag}::<fn>' or '_mbf_${mod_tag}_<fn>')"
                errors=$((errors + 1))
            else
                printf '[OK]   Function convention: %s\n' "$fn_name"
            fi
        done < <(grep -E '^[[:space:]]*function[[:space:]]+[a-zA-Z0-9_:]+' "$target" | sed -E 's/^[[:space:]]*function[[:space:]]+([a-zA-Z0-9_:]+).*/\1/')
    fi

    # 2. Check `mbf::use` statements and resolve every module
    local line mods m resolved_mod
    while IFS= read -r line; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^[[:space:]]*mbf::use[[:space:]]+(.+)$ ]]; then
            mods="${BASH_REMATCH[1]%%#*}"
            for m in $mods; do
                m="${m//[\"\']/}"
                if resolved_mod="$(_mbf_resolve_path "$m")"; then
                    printf '[OK]   mbf::use %-18s -> %s\n' "$m" "$resolved_mod"
                else
                    mbf::log::error "Unresolved mbf::use module '$m' (MBF_EXT_PATH='${MBF_EXT_PATH:-}')"
                    errors=$((errors + 1))
                fi
            done
        fi
    done < "$target"

    # 3. Check `mbf::template::render` / `mbf::template::resolve` literal references
    local tpl_ref resolved_tpl
    while IFS= read -r line; do
        line="${line%$'\r'}"
        if [[ "$line" =~ mbf::template::(render|resolve)[[:space:]]+[\"\']([^\"\'\$\;[:space:]]+)[\"\'] ]]; then
            tpl_ref="${BASH_REMATCH[2]}"
            if resolved_tpl="$(mbf::template::resolve "$tpl_ref")"; then
                printf '[OK]   Template %-18s -> %s\n' "$tpl_ref" "$resolved_tpl"
            else
                mbf::log::error "Unresolved template '$tpl_ref' (MBF_TEMPLATE_PATH='${MBF_TEMPLATE_PATH:-}')"
                errors=$((errors + 1))
            fi
        fi
    done < "$target"

    # 4. Check for non-standard function declarations (missing `function` keyword needed by exporter)
    if grep -Eq '^[[:space:]]*[a-zA-Z0-9_:]+[[:space:]]*\(\)[[:space:]]*\{' "$target"; then
        mbf::log::warn "Found function declared without 'function' keyword in $base_name (use 'function name() {' for exporter compatibility)"
        warnings=$((warnings + 1))
    fi

    printf '=== Summary: %d error(s), %d warning(s) ===\n' "$errors" "$warnings"
    [ "$errors" -eq 0 ]
}
