#!/usr/bin/env bash

##########
# Section 0. Framework features and Environment parameters

DIR="${BASH_SOURCE%/*}"
PRINTF="$(which printf)"
SED="$(which sed)"
# Manual of script based on this framework.sh. if specified, will be printed when -h or --help is given or no input param is given
USAGE=""
# requirements of script based on this framework.sh. Parameters split by space
I7R_REQUIREMENTS=""

# import bash libraries
# in early days, we just have some libraries so all placed in same directory as framework.sh
# need to declare after requirements of framework.sh, take 1 parameter for library name, example below 
# source $DIR/../base/framework.sh
# _import config
# _import compiler
# _import obfuscator
function _import() {
    local lib=$1
    # check if library exist
    if [ -f "$DIR/$lib.sh" ]; then
        source $DIR/$lib.sh
    else
        echo "Library $lib not found"
        exit 1
    fi
}

# get current working directory
function get_pwd() {
    echo $(pwd)
}

# get current directory of script file
function get_script_dir() {
    echo $(dirname "${BASH_SOURCE[1]}")
}


##########
# Section 1. Basic functions

# check to see if fucntion exist
# if (function_exists fn_name); then
function function_exists() {
  # appended double quote is an ugly trick to make sure we do get a string -- if $1 is not a known command, type does not output anything
  [ `type -t $1`"" == 'function' ]
}

# print string with color and timestamp
# print_with_color "message to print"
# supported colors are : red, green, yellow, blue, purple, cyan, white
function print_with_color() {
    local message=$1
    local color=$2
    local activeColor='\033[1;33m' # Yellow - default
    case $color in
        red)
            local activeColor='\033[0;31m'
            ;;
        green)
            local activeColor='\033[0;32m'
            ;;
        purple)
            local activeColor='\033[0;35m'
            ;;
        cyan)
            local activeColor='\033[0;36m'
            ;;
        white)
            local activeColor='\033[1;37m'
            ;;
    esac

    local timeColor='\033[0;34m' # Light Grey
    local timestamp="$(date +'%Y-%m-%d / T%H:%M:%S%z')"
    local colorReset='\033[0m' # Color Reset

  # ANSI escape code
  # Black        0;30     Dark Gray     1;30
  # Red          0;31     Light Red     1;31
  # Green        0;32     Light Green   1;32
  # Brown/Orange 0;33     Yellow        1;33
  # Blue         0;34     Light Blue    1;34
  # Purple       0;35     Light Purple  1;35
  # Cyan         0;36     Light Cyan    1;36
  # Light Gray   0;37     White         1;37

  $PRINTF "${timeColor}$timestamp ${activeColor}$message${colorReset}\n"
}

# print step in pre-formatted template . to make step more visible and consistent
function print_step_msg() {
    local message=$1
    local color=$2

    print_with_color "[ $message ]" $color
}

# equivalent to in_array
# param $1 is needle
# param $2 is haystack
function in_list() {
    local NEEDLE="$1"
    shift
    local HAYSTACK="$@"

    for line in $HAYSTACK; do
        if [ "$line" == "$NEEDLE" ]; then
            echo "yes"
            return
        fi
    done

    echo "no"
}

# check file contain string or not
# param $1 is file
# param $@ is string
function in_file() {
    local FILE="$1"
    shift
    local NEEDLE="$@"

    if grep -q "$NEEDLE" "$FILE"; then
        echo "yes"
    else
        echo "no"
    fi
}


##########
# Section 2. sudo & command execution

function read_sudo_pwd() {
    read -s -p "This script requires sudo privileges. [sudo] password for $USER: " sudo_pwd
    echo ""
    until (echo $sudo_pwd | sudo -S echo '' 2>/dev/null)
    do
        read -s -p "Wrong password / Insufficient permission. Try again : " sudo_pwd
        echo ""
    done
}

# initialize sudo mode
function initialize_sudo() {
    if [ $(id -u) != 0 ]; then
        read_sudo_pwd
    fi
}

# execute commands with description. support sudo
# if command failed, put error log to /tmp/isevenr_bash_framework.log
# support _sudo_required_ place holder to replace with sudo in command chain
# TODO: handle failed command in exec functions. print to log file in /tmp
# TODO: support environment variable I7R_LOGGING
# TODO: handle special chars in sudo password, see line 171
# param $@ command
function run_cmd() {
    local command="$@"

    if [ "$SUDO_REQUIRED" == "1" ];then
        command="${command/_sudo_required_/sudo}"
        print_with_color "Executing :\nsudo $command"
        if [ "$I7R_DRYRUN" != "1" ];then
            eval "echo $sudo_pwd | sudo -S $command"
        fi
    else
        command="${command/_sudo_required_ /}"
        print_with_color "Executing :\n$command"
        if [ "$I7R_DRYRUN" != "1" ];then
            eval $command

            # if eval command not finished with success code, exit
            if [ $? -ne 0 ]; then
                print_with_color "Error: $command" red
                exit 1
            fi
        fi
    fi

}

# run command by other user role
# sudo is required
function run_cmd_by_user() {
    local user=$1
    shift
    local command="$@"

    if [ "$SUDO_REQUIRED" == "1" ];then
        print_with_color "Executing :\nsudo -H -u $user bash -c '$command'"
        eval "sudo -H -u $user bash -c '$command'"
    fi
}

# run all executable parts included in a directory
# part must not have .sh extension and executable
# example run_parts_by_dir /home/thanhnd/tmp/scripts/
function run_parts_by_dir() {
    local dir=$1

    if [ -d $dir ]; then
        run-parts -v $dir
    fi
}

# run all script included in a directory
# support wide range of scripts : python, bash, ruby, php ...
# NOTE: interpreter is required to run the script. white space is not allowed
# example run_scripts_by_dir /home/thanhnd/tmp/scripts/ bash sh
function run_scripts_by_dir() {
    local dir=$1
    local interpreter=$2
    local ext=$3

    if [ -d $dir ]; then
        find $dir -maxdepth 1 -type f -name "*.$ext" -print0 | while read -d $'\0' file
        do
            print_with_color "Executing :\n$interpreter $file"
            eval "$interpreter $file"
        done
    fi
}

# execute function with parameter 
# if env variable I7R_DRYRUN is set to 1, only print command
# example : execute main_function_name $@
function execute() {
    local entry=$1
    shift 1
    local params="$@"

    if [ "$I7R_DRYRUN" == "1" ];then
        print_with_color "Output command(s) only"
    fi

    if [ "$params" == "" ] && [ "$USAGE" != "" ]; then
        echo "$USAGE"
        return 1
    fi

    $entry $params
}


# if $I7R_REQUIREMENTS is set, check if all requirements are met
function check_requirements() {
    for req in $I7R_REQUIREMENTS; do
        if [ -z `command -v $req` ] ; then
            echo "required program \"$req\" could not be found"
            exit
        fi
    done
}

##########
# Section 3. background / repetitive mode

# execute command mulitple times, set sleep_time to 0 to run all commands instantly
# example : run_times 5 0 ls -l
function run_times() {
    local times=$1
    local sleep_time=$2
    shift 2
    local command="$@"

    for i in `seq $times`; do
        run_cmd "$command"
        sleep $sleep_time
    done
}

# run function in background with sleep param
# example : run_continously sleep cmd
function run_continously() {
    local sleep_time=$1
    shift
    local command="$@"

    while true
    do
        run_cmd "$command"
        sleep $sleep_time
    done
}

##########
# Section 7. integrate with unix default utilities

# check if a program is installed before running
# param $1 is program name
# param $2 trigger exit or warning only, optional - default is warning
# param $3 is program version
# return 0 if program is valid, 1 if not
# TODO: write test
function validate_program() {
    local program=$(which $1)
    local trigger=$2
    local version=$3

    if [ -z `command -v $program` ] ; then
        if [ "$trigger" == "exit" ]; then
            print_with_color "required program \"$program\" could not be found" red
            exit
        else
            print_with_color "required program \"$program\" could not be found" yellow
        fi

        return 1
    fi

    if [ "$version" != "" ]; then
        local program_version=`$program --version | head -n 1 | awk '{print $NF}'`
        if [ "$program_version" != "$version" ]; then
            print_with_color "required program \"$program\" version $version is required" red
            exit
        fi
    fi

    return 0
}


##########
# Section 8. log & report


##########
# Section 9. initialize framework

function init() {
    if [ "$SUDO_REQUIRED" == "1" ];then
        initialize_sudo
    fi
}
init
