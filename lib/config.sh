#!/usr/bin/env bash
# mbf module: config
# Configuration file manipulation utilities (key-value, lines, text replacement, YAML via yq)

# Internal helper: escape string for use in sed regex pattern (delimiter: |)
function _mbf_escape_sed_pattern() {
    printf '%s' "$1" | sed -e 's/[][\/.^$*|]/\\&/g'
}

# Internal helper: escape string for use in sed replacement (delimiter: |)
function _mbf_escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'
}

# Modify config value in file (supports `key = value` format)
# Example: modify_config_value /tmp/test_framework.conf color red
function modify_config_value() {
    local CONFIG_FILE="$1"
    local TARGET_KEY="$2"
    local REPLACEMENT_VALUE="$3"

    if [ -e "$CONFIG_FILE" ]; then
        local esc_key
        local esc_val
        esc_key="$(_mbf_escape_sed_pattern "$TARGET_KEY")"
        esc_val="$(_mbf_escape_sed_replacement "$REPLACEMENT_VALUE")"
        if function_exists run_cmd; then
            run_cmd "sed -i -e \"\\|$esc_key| s|=.*|= $esc_val|\" \"$CONFIG_FILE\""
        else
            sed -i -e "\|$esc_key| s|=.*|= $esc_val|" "$CONFIG_FILE"
        fi
    fi
}

# Read config value by key from a `key = value` or `key=value` file
# Example: get_config_value /tmp/test_framework.conf color
function get_config_value() {
    local CONFIG_FILE="$1"
    local TARGET_KEY="$2"

    if [ -e "$CONFIG_FILE" ]; then
        grep -E "^[[:space:]]*${TARGET_KEY}[[:space:]]*=" "$CONFIG_FILE" | tail -n 1 | sed -E 's/^[^=]*=[[:space:]]*//'
    fi
}

# Insert a config line at the end of a file
# Example: insert_config /tmp/test_framework.conf "color = black"
function insert_config() {
    local CONFIG_FILE="$1"
    shift
    local LINE="$*"

    if [ -e "$CONFIG_FILE" ]; then
        local dryrun="${MBF_DRYRUN:-${I7R_DRYRUN:-0}}"
        if [ "${SUDO_REQUIRED:-0}" == "1" ]; then
            run_cmd "printf '%s\n' \"$LINE\" | _sudo_required_ tee -a \"$CONFIG_FILE\" >/dev/null"
        elif function_exists run_cmd; then
            print_with_color "Executing :\nappend '$LINE' >> $CONFIG_FILE"
            if [ "$dryrun" != "1" ]; then
                printf '%s\n' "$LINE" >> "$CONFIG_FILE"
            fi
        else
            printf '%s\n' "$LINE" >> "$CONFIG_FILE"
        fi
    fi
}

# Idempotently ensure a line exists in a config file (updates key if key=val, or appends if missing)
# Example: ensure_config /tmp/test_framework.conf "color = black"
function ensure_config() {
    local CONFIG_FILE="$1"
    shift
    local LINE="$*"

    if [ ! -e "$CONFIG_FILE" ]; then
        touch "$CONFIG_FILE"
    fi

    if grep -Fqx "$LINE" "$CONFIG_FILE" 2>/dev/null; then
        return 0
    fi

    insert_config "$CONFIG_FILE" "$LINE"
}

# Delete lines matching a pattern from a file
# Example: delete_line /tmp/test_framework.conf "memory_limit"
function delete_line() {
    local CONFIG_FILE="$1"
    shift
    local MATCH="$1"

    if [ -e "$CONFIG_FILE" ]; then
        local esc_match
        esc_match="$(_mbf_escape_sed_pattern "$MATCH")"
        if function_exists run_cmd; then
            run_cmd "sed -i \"\\|$esc_match|d\" \"$CONFIG_FILE\""
        else
            sed -i "\|$esc_match|d" "$CONFIG_FILE"
        fi
    fi
}

# Replace an entire line matching a pattern with new line content
# Example: replace_line /tmp/test_framework.conf "default_socket_timeout" "default_socket_timeout = 60"
function replace_line() {
    local CONFIG_FILE="$1"
    local MATCH="$2"
    shift 2
    local NEWLINE="$*"

    if [ -e "$CONFIG_FILE" ]; then
        local esc_match
        local esc_replacement
        esc_match="$(_mbf_escape_sed_pattern "$MATCH")"
        esc_replacement="$(_mbf_escape_sed_replacement "$NEWLINE")"
        if function_exists run_cmd; then
            run_cmd "sed -i \"s|.*${esc_match}.*|${esc_replacement}|\" \"$CONFIG_FILE\""
        else
            sed -i "s|.*${esc_match}.*|${esc_replacement}|" "$CONFIG_FILE"
        fi
    fi
}

# Replace all occurrences of a text string in a file (supports slashes/paths safely)
# Example: replace_text_in_file /etc/systemd/system/vncserver@.service "_vnc_user_" "thanh.vnc"
function replace_text_in_file() {
    local CONFIG_FILE="$1"
    local MATCH="$2"
    shift 2
    local REPLACEMENT="$*"

    if [ -e "$CONFIG_FILE" ]; then
        local esc_match
        local esc_replacement
        esc_match="$(_mbf_escape_sed_pattern "$MATCH")"
        esc_replacement="$(_mbf_escape_sed_replacement "$REPLACEMENT")"
        if function_exists run_cmd; then
            run_cmd "sed -i \"s|${esc_match}|${esc_replacement}|g\" \"$CONFIG_FILE\""
        else
            sed -i "s|${esc_match}|${esc_replacement}|g" "$CONFIG_FILE"
        fi
    fi
}

# Get line number of the first occurrence of a text pattern in a file
# Returns line number or "notfound"
function get_text_linenumber() {
    local FILE="$1"
    shift
    local PATTERN="$*"

    if [ -e "$FILE" ]; then
        local LINENUMBER
        LINENUMBER="$(grep -m1 -n -F "$PATTERN" "$FILE" | cut -d: -f1)"
        if [ -n "$LINENUMBER" ]; then
            echo "$LINENUMBER"
            return 0
        fi
    fi

    echo "notfound"
}

# Append text after a specific line number
# Example: append_after_linenumber docker-compose.yml 10 "SENDMAIL_PATH=/usr/local/bin/mhsendmail"
function append_after_linenumber() {
    local FILE="$1"
    local LINENUM="$2"
    shift 2
    local TEXT="$*"

    if [ -e "$FILE" ]; then
        local esc_text
        esc_text="$(_mbf_escape_sed_replacement "$TEXT")"
        run_cmd "sed -i '${LINENUM}a ${esc_text}' \"$FILE\""
    fi
}

# Edit YAML with yq: append item to an array node
function yq_append_array_item() {
    local FILE="$1"
    local NODE="$2"
    local VALUE="$3"

    run_cmd "yq -i eval '.${NODE} += [\"${VALUE}\"]' \"$FILE\""
}

# Edit YAML with yq: set or append a scalar node
function yq_append_node() {
    local FILE="$1"
    local NODE="$2"
    local VALUE="$3"

    run_cmd "yq -i eval '.${NODE} = \"${VALUE}\"' \"$FILE\""
}
