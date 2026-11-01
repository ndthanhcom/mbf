#! /bin/bash
# main test file for framework functionalities
source ~/.init/scripts/base/framework.sh
_import config

SUDO_REQUIRED="0"
DRY_RUN="0"

# uncomment to test USAGE
#USAGE="\
#    Test framework functionalities
#"

# test config.sh
function test_config() {
    # create temporary config file
    print_with_color "initialize /tmp/test_framework.conf"
    touch /tmp/test_framework.conf

    if (function_exists insert_config); then
        insert_config /tmp/test_framework.conf '127.0.0.1 = ndthanh.net'
        print_with_color "/tmp/test_framework.conf content"
        cat /tmp/test_framework.conf
    fi

    if (function_exists modify_config_value); then
        modify_config_value /tmp/test_framework.conf 127.0.0.1 isevenr.com
        print_with_color "/tmp/test_framework.conf content"
        cat /tmp/test_framework.conf
    fi

    if (function_exists delete_line); then
        insert_config /tmp/test_framework.conf 'memory_limit = 4G'
        print_with_color "/tmp/test_framework.conf content"
        cat /tmp/test_framework.conf

        delete_line /tmp/test_framework.conf "memory_limit"
        print_with_color "/tmp/test_framework.conf content"
        cat /tmp/test_framework.conf
    fi

    if (function_exists replace_line); then
        insert_config /tmp/test_framework.conf "default_socket_timeout = 32"
        print_with_color "/tmp/test_framework.conf content"
        cat /tmp/test_framework.conf

        replace_line /tmp/test_framework.conf "default_socket_timeout"  "default_socket_timein = 64"
        print_with_color "/tmp/test_framework.conf content"
        cat /tmp/test_framework.conf
    fi

    if (function_exists replace_text_in_file); then
        insert_config /tmp/test_framework.conf "aa bb cc"
        insert_config /tmp/test_framework.conf "bb cc dd"
        insert_config /tmp/test_framework.conf "cc dd ee"
        print_with_color "/tmp/test_framework.conf content"
        cat /tmp/test_framework.conf

        replace_text_in_file /tmp/test_framework.conf "bb" "ee"
        print_with_color "/tmp/test_framework.conf content"
        cat /tmp/test_framework.conf
    fi

    # remove test file
    rm /tmp/test_framework.conf
}



# test basic functions
function test_basic() {
    touch /tmp/test_framework.conf

    if (function_exists insert_config); then
        insert_config /tmp/test_framework.conf '127.0.0.1   ndthanh.net'
    fi
    inlist1=$(in_list 73 74 81)
    inlist2=$(in_list 74 74 81)
    infile1=$(in_file /tmp/test_framework.conf 127.0.0.1)
    infile2=$(in_file /tmp/test_framework.conf abcxyz)
    print_with_color "in_list test result 1 : $inlist1"
    if [ "$inlist1" == "no" ]; then
        echo "not in list"
    fi
    print_with_color "in_list test result 2 : $inlist2"
    if [ $inlist2 == "yes" ]; then
        echo "in list"
    fi
    print_with_color "in_file test result 1 : $infile1"
    print_with_color "in_file test result 2 : $infile2"

    # remove test file
    rm /tmp/test_framework.conf

    run_cmd "echo \"run :Copilot setup in Vim to install github copilot - TEST TEXT\""
}



# test background / repetitive
function test_background() {
    print_with_color "running date command 5 times instantly"
    run_times 5 0 date

    interval=1
    print_with_color "running date command until Ctrl+C. interval $interval second"
    run_continously $interval date
}


# test params assignments
function test_params_assignment() {
    run_cmd "CONFIG=\"MAGENTO_BASE_URL=http://magento2.docker/ MODULE_WHITELIST=Magento_Framework,Magento_ConfigurableProductWishlist,Magento_ConfigurableProductCatalogSearch\""
    eval $CONFIG
    run_cmd "echo $CONFIG"
    run_cmd "echo $MAGENTO_BASE_URL"
    run_cmd "echo $MODULE_WHITELIST"

    print_with_color "Multi line json config file"
    print_with_color "Adding to auth.json"
	echo "{" >> auth.json
	echo "    \"http-basic\": {" >> auth.json
	echo "        \"repo.magento.com\": {" >> auth.json
	echo "            \"username\": \"4413a08d5a15b923d3dee1c2e42e2223\"," >> auth.json
	echo "            \"password\": \"0008be37ff7afd0b2b88f7ed42ab3a13\"" >> auth.json
	echo "        }" >> auth.json
	echo "    }" >> auth.json
	echo "}" >> auth.json
	run_cmd "cat auth.json"
	run_cmd "rm auth.json"
}

# test execution functions
function test_execution() {
    SUDO_REQUIRED="1"
    run_cmd_by_user tran "whoami"
    run_parts_by_dir $DIR/scripts
    run_scripts_by_dir $DIR/scripts bash sh
    run_scripts_by_dir $DIR/scripts php php
    SUDO_REQUIRED="0"
}

function check_params() {
    echo "Check params"
    echo $1
    echo $2
    echo $3
    echo $5
    echo "Check end."
}

function test_run_cmd() {
    # executed failed cmd
    run_cmd "ls -l /tmp/abc"
}



# execute tests
function run_tests() {
    test_basic
    test_config
    #test_params_assignment
    #test_background
    #check_params "test" 1
    #test_execution
    test_run_cmd
}

execute run_tests $@
