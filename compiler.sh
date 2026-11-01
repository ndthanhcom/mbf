#!/usr/bin/env bash
# this standalone script build binary file for given bash script using shc
# output to the current directory
# shc is required. install with: sudo apt install shc

# Example: cd /path/to/target/script_dir && bash /path/to/compiler.sh script.sh

DIR="${BASH_SOURCE%/*}"
source $DIR/framework.sh
source $DIR/obfuscator.sh

# after including framework.sh, obfuscator.sh using DIR of this script compile.sh - change DIR to pwd to support DIR param from the script
DIR=$(pwd)

# merge scripts included by source
# loop through bash script. replace `source` with file content, then output to a new file
# only `source` is supported, `.` is not supported
function process_inline() {
    local file=$1
    local merged_file="m_$(basename $file)"
    local pattern="(^source)\s.*.sh"
    rm -f $merged_file

    while read line; do
        if [[ $line =~ $pattern ]]; then
            s_file="$(echo $line | cut -d' ' -f2)"
            # use eval + cat to get included file content
            eval "cat $s_file" >> $merged_file
        else
            echo "$line" >> $merged_file
        fi
    done <$file

    #echo $merged_file
}

# to compile multiple files, use alias or separate bash script
function compile() {
    local script=$1

    if [ -z "$script" ]; then
        print_with_color "No script file given" "red"
        exit 1
    fi

    # merge scripts included by source. omit $(process_inline $script) to see error during processing
    process_inline $script
    local m_script="m_$(basename $script)"

    # obfuscate m_script , prepare for compilation
    obfuscate $m_script
    local o_script="o_$(basename $m_script)"

    local script_content=$(cat $o_script)
    echo "#!/bin/bash" > $o_script
    echo "$script_content" >> $o_script

    # compile script with shc
    local output="$(basename $o_script)"
    output=$(echo "${output%.*}")
    if [ -z `command -v shc` ] ; then
        print_with_color "shc (shell script compiler) not found. please install it first" "red"
        exit 1
    else
        run_cmd "CFLAGS=\"-static\" shc -r -f $o_script -o $output"
        print_with_color "Compiled file is : $output" "green"
    fi

    # cleanup temp files used for generation
    rm -f $o_script.x.c $o_script $m_script
}

compile $@
