#!/usr/bin/env bash
# mbf module: compiler
# Export standalone script and optionally obfuscate + compile into a native binary with shc

function compile() {
    local script="$1"

    if [ -z "$script" ]; then
        print_with_color "No script file given" "red"
        return 1
    fi

    local m_script="m_$(basename "$script")"
    mbf_export_script "$script" "$m_script"

    local target_script="$m_script"
    if command -v bash-obfuscate >/dev/null 2>&1; then
        obfuscate "$m_script"
        local o_script="o_$(basename "$m_script")"
        local script_content
        script_content="$(cat "$o_script")"
        printf '#!/bin/bash\n%s\n' "$script_content" > "$o_script"
        target_script="$o_script"
    fi

    local output
    output="$(basename "$target_script")"
    output="${output%.*}"

    if ! command -v shc >/dev/null 2>&1; then
        print_with_color "shc (shell script compiler) not found. Standalone exported script saved at: $m_script" "yellow"
        return 1
    else
        run_cmd "CFLAGS=\"-static\" shc -r -f $target_script -o $output"
        print_with_color "Compiled file is : $output" "green"
        rm -f "${target_script}.x.c" "$target_script" "$m_script"
    fi
}
