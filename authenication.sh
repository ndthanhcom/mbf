# this is a library for inclusion

# Perform dynamic password verification for public executable binary file.
# dynamic password is year + SEED + month + date
# include this script before the main script
# 
# Example: source /path/to/this/authenication.sh
# then run export I7R_TOKEN="generated_token" on target machine

SEED="R1"

function validate_token() {
    local token=$1
    local valid_token=$(generate_token)

    exit;
}

function generate_token() {
    echo ""
}
