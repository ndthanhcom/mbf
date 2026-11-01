# this is a library for inclusion

# Process parameters.
# this should be included after framework.sh and before the main script
# $PARAMS defines parameter in the main script

USAGE=$(cat <<-MULTILINE
    This is line one.
    This is line two.
    This is line three.
MULTILINE
)

if [ -z "$PARAMS" ]; then
    PARAMS="v;verbose;Print output to terminal to see what is happening"
else
    PARAMS="$PARAMS\nv;verbose;Print output to terminal to see what is happening"
fi

# check for parameter and capture value. otherwise, display message
# return 0, 1 or 2. support verbose param
function process_param() {
    for p in $PARAMS; do
        $PRINTF $p
    done

    $PRINTF 0
}

# using given parameters list to translate inputs parameter
# example: process_params parameter_list
function process_params() {
    while [ $# -gt 0 ]; do
        shift_step=$(process_param $PNAME $ALL)
        if [ $shift_step == "0" ]; then
            if (function_exists print_with_color); then
                print_with_color "Invalid parameter '$1'. \n ### PLEASE SEE HELP CONTENT BELOW FOR MORE INFORMATION. ###\n\n\n"
            fi
            print_help
            exit 1 # error status
        else
            shift $shift_step
        fi
    done
}
