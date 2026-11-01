# this is a library for inclusion

# obfuscate bash script.
# requirements : nodejs v12+, bash-obfuscator https://www.npmjs.com/package/bash-obfuscate
# npm install -g bash-obfuscate

# should be included after framework.sh
# usage : obfuscate setup_docker.sh
# output : o_setup_docker.sh

function obfuscate() {
    local script=$1

    if [ -z "$script" ] ; then
        print_with_color "No script file given" "red"
        exit 1
    fi
    local output="o_$(basename $script)"

    if [ -z `command -v bash-obfuscate` ] ; then
        print_with_color "bash-obfuscate not found. please install it first" "red"
        exit 1
    else
        # don't use run_cmd or it will cause trouble : returned file name include the print_with_color output from run_cmd
        bash-obfuscate $script -o $output
    fi

    #echo $output
}
