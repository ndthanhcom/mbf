#!/usr/bin/env bash
# mbf module: obfuscator
# Obfuscate bash script using bash-obfuscate (npm install -g bash-obfuscate)

function obfuscate() {
    local script="$1"

    if [ -z "$script" ]; then
        print_with_color "No script file given" "red"
        return 1
    fi
    local output="o_$(basename "$script")"

    if ! command -v bash-obfuscate >/dev/null 2>&1; then
        print_with_color "bash-obfuscate not found. please install it first" "red"
        return 1
    else
        bash-obfuscate "$script" -o "$output"
    fi
}
