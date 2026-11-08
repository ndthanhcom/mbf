#!/usr/bin/env bash
# mbf module: auth
# Dynamic date+SEED token generation and validation

SEED="${SEED:-R1}"

# Generate dynamic token: YYYY + SEED + MM + DD
function generate_token() {
    local seed="${1:-${SEED:-R1}}"
    printf '%s%s%s\n' "$(date +'%Y')" "$seed" "$(date +'%m%d')"
}

# Validate token against generated dynamic token (uses $1 or $I7R_TOKEN or $MBF_TOKEN)
function validate_token() {
    local token="${1:-${MBF_TOKEN:-${I7R_TOKEN:-}}}"
    local valid_token
    valid_token="$(generate_token)"

    if [ -z "$token" ] || [ "$token" != "$valid_token" ]; then
        if function_exists print_with_color; then
            print_with_color "Authentication failed: invalid or missing token" red
        else
            echo "Authentication failed: invalid or missing token" >&2
        fi
        return 1
    fi
    return 0
}
