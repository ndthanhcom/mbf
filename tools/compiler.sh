#!/usr/bin/env bash
# ==============================================================================
# mbf build tool: compiler
# Exports a standalone script, optionally obfuscates via plugins/obfuscator.sh,
# and compiles into a native binary using `shc`.
# ==============================================================================

# Usage: mbf::compiler::run <script.sh> [-o output_bin] [--obfuscate]
function mbf::compiler::run() {
    local script="" output="" use_obfuscate=0

    while [ $# -gt 0 ]; do
        case "$1" in
            -o|--output)  output="$2"; shift 2 ;;
            --obfuscate)  use_obfuscate=1; shift 1 ;;
            *)            [ -z "$script" ] && script="$1"; shift 1 ;;
        esac
    done

    if [ -z "$script" ] || [ ! -f "$script" ]; then
        mbf::log::error "mbf::compiler::run: valid script file is required"
        return 1
    fi

    # Load exporter tool
    # shellcheck disable=SC1091
    source "${MBF_HOME}/tools/exporter.sh"

    local exported="m_$(basename "$script")"
    mbf::exporter::run "$script" -o "$exported" || return 1

    local target_script="$exported"
    if [ "$use_obfuscate" -eq 1 ] || command -v bash-obfuscate >/dev/null 2>&1; then
        mbf::use obfuscator
        local obf_script="o_$(basename "$exported")"
        if mbf::obfuscator::run "$exported" "$obf_script"; then
            local content
            content="$(cat "$obf_script")"
            printf '#!/usr/bin/env bash\n%s\n' "$content" > "$obf_script"
            target_script="$obf_script"
        fi
    fi

    output="${output:-$(basename "${script%.*}")}"

    if ! mbf::check::cmd "shc"; then
        mbf::log::warn "shc (shell script compiler) not found. Standalone exported script saved at: $exported"
        return 1
    fi

    CFLAGS="-static" shc -r -f "$target_script" -o "$output"
    local rc=$?
    rm -f "${target_script}.x.c" "o_$(basename "$exported")" "$exported"
    if [ $rc -eq 0 ]; then
        mbf::log::ok "Compiled binary: $output"
    fi
    return $rc
}
