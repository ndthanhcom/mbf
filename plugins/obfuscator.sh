#!/usr/bin/env bash
# mbf:requires log check
# ==============================================================================
# mbf plugin: obfuscator
# Obfuscate bash scripts using bash-obfuscate (npm install -g bash-obfuscate)
# ==============================================================================

# Obfuscate a bash script into `<output_file>` (defaults to `o_<basename>`)
# Usage: mbf::obfuscator::run <input.sh> [output.sh]
function mbf::obfuscator::run() {
    local script="${1:-}"
    local output="${2:-}"

    if [ -z "$script" ] || [ ! -f "$script" ]; then
        mbf::log::error "mbf::obfuscator::run: valid script file is required"
        return 1
    fi

    output="${output:-o_$(basename "$script")}"

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would obfuscate $script -> $output"
        return 0
    fi

    if ! mbf::check::cmd "bash-obfuscate"; then
        mbf::log::error "bash-obfuscate not found. Install with: npm install -g bash-obfuscate"
        return 1
    fi

    bash-obfuscate "$script" -o "$output"
}
