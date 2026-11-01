# this is a library for inclusion

# interact with config files.
# modify config value in file.
# supported format:
#   require `=` : 127.0.0.1 = isevenr.com

# example modify_config_value /tmp/test_framework.conf color red

function modify_config_value() {
    local CONFIG_FILE=$1
    local TARGET_KEY=$2
    local REPLACEMENT_VALUE=$3
    local CMD="sed -i -e '/$TARGET_KEY/ s/=.*/= $REPLACEMENT_VALUE/' $CONFIG_FILE"

    if (function_exists run_cmd) ; then
        if [ -e $CONFIG_FILE ]; then
            run_cmd $CMD
        fi
    fi
}

# insert_config value to file.
# TODO: support special character
# example : insert_config /tmp/test_framework.conf "color = black"
function insert_config() {
    local CONFIG_FILE=$1
    shift
    local LINE="$@"
    local CMD="echo $LINE | _sudo_required_ tee -a $CONFIG_FILE"

    if (function_exists run_cmd) ; then
        if [ -e $CONFIG_FILE ]; then
            run_cmd $CMD
        fi
    fi
}

# delete a line from file by given pattern
# example : delete_line /tmp/test_framework.conf "memory_limit"
function delete_line() {
    local CONFIG_FILE=$1
    shift
    local MATCH="$1"

    if (function_exists run_cmd) ; then
        if [ -e $CONFIG_FILE ]; then
            run_cmd "sed -i \"/$MATCH/d\" $CONFIG_FILE"
        fi
    fi
}

# replace a whole line from file by given pattern and new line content
# example : replace_line /tmp/test_framework.conf "default_socket_timeout" "default_socket_timeout = 60"
function replace_line() {
    local CONFIG_FILE=$1
    local MATCH="$2"
    shift 2
    local NEWLINE="$@"

    if (function_exists run_cmd) ; then
        if [ -e $CONFIG_FILE ]; then
            run_cmd "sed -i \"/$MATCH/c $NEWLINE\" $CONFIG_FILE"
        fi
    fi
}

# replace a text with a new one for whole file
# example : replace_text_in_file /etc/systemd/system/vncserver@.service "_vnc_user_" "thanh.vnc"
function replace_text_in_file() {
    local CONFIG_FILE=$1
    local MATCH="$2"
    shift 2
    local REPLACEMENT="$@"

    if (function_exists run_cmd) ; then
        if [ -e $CONFIG_FILE ]; then
            run_cmd "sed -i 's/$MATCH/$REPLACEMENT/g' $CONFIG_FILE"
        fi
    fi
}

# get a line number of the first occurrence of a text in a file
# example : get_text_linenumber "SENDMAIL_PATH=/usr/local/bin/mhsendmail"
function get_text_linenumber() {
    local FILE="$1"
    shift
    local PATTERN="$@"

    if [ -e $FILE ]; then
        local LINENUMBER=$(grep -m1 -n "$PATTERN" $FILE | cut -d: -f1)
        echo $LINENUMBER
    fi
    
    echo "notfound"
}

# append a text after a line number
# example : append_after_linenumber docker-compose.yml 10 "SENDMAIL_PATH=/usr/local/bin/mhsendmail"
function append_after_linenumber() {
    local FILE="$1"
    local LINEAPPEND="$2a"
    #local LINEINSERT="$2i"
    shift 2
    local TEXT="$@"

    run_cmd "sed -i '$LINEAPPEND $TEXT' $FILE"
}

# edit yaml with yq , add line to array for specified node
# yq is required, source https://github.com/mikefarah/yq
# install yq with wget instead of snap to avoid error. use below commands
# sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
# sudo chmod a+x /usr/local/bin/yq
# removing yaml content with delete_line
function yq_append_array_item() {
    local FILE="$1"
    local NODE="$2"
    local VALUE="$3"

    run_cmd "yq -i eval '.${NODE} += [\"${VALUE}\"]' $FILE"
}

function yq_append_node() {
    local FILE="$1"
    local NODE="$2"
    local VALUE="$3"

    run_cmd "yq -i eval '.${NODE} = \"${VALUE}\"' $FILE"
}
