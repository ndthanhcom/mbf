#! /bin/bash
# main test file for framework functionalities
DIR="${BASH_SOURCE%/*}"
source $DIR/../framework.sh
source $DIR/../config.sh
SUDO_REQUIRED="0"
DRY_RUN="0"
TEST_FILE="$DIR/tmp/docker-test.yml"

function generate_yml_test_file() {
    rm -f $TEST_FILE
	echo "version: '3'" >> $TEST_FILE
	echo "services:" >> $TEST_FILE
	echo "  fpm:" >> $TEST_FILE
	echo "    image: 'magento/magento-cloud-docker-php:_docker_cloud_php_-fpm-_docker_cloud_version_'" >> $TEST_FILE
	echo "    env_file: .env" >> $TEST_FILE
	echo "    volumes:" >> $TEST_FILE
	echo "      - '.:/app'" >> $TEST_FILE
	echo "      - '.docker/scripts/magento.sh:/usr/local/bin/magento.sh'" >> $TEST_FILE
	echo "    environment:" >> $TEST_FILE
	echo "      - MAGENTO_ROOT=/app" >> $TEST_FILE
	echo "      - SENDMAIL_PATH=/usr/local/bin/mhsendmail --smtp-addr=\"mailhog:1025\"" >> $TEST_FILE
	echo "    networks:" >> $TEST_FILE
	echo "      - magento" >> $TEST_FILE
	echo "    depends_on:" >> $TEST_FILE
	echo "      - db" >> $TEST_FILE
    chmod 777 $TEST_FILE
}

function check_yml_test_file() {
    if [ -e $TEST_FILE ]; then
        cat $TEST_FILE
        sleep 1
    fi
}

# test execution functions
function test_insert_config() {
    echo "Check params"
}

function test_modify_config_value() {
    run_cmd_by_user tran "whoami"
}

function test_delete_line() {
    echo "Check params"
}

function test_replace_line() {
    echo "Check params"
}

function test_replace_text_in_file() {
    echo "Check params"
}

function test_get_text_linenumber() {
    echo "Check params"
}

function test_append_after_linenumber() {
    echo "Check params"
}

# execute tests
function run_tests() {
    # test yml
    generate_yml_test_file

    print_with_color "edit existing array"
    yq_append_array_item $TEST_FILE "services.fpm.environment" "MAGENTO_RUN_MODE=developer"
    check_yml_test_file

    print_with_color "add new array"
    yq_append_array_item $TEST_FILE "services.fpm.description" "test"
    check_yml_test_file

    print_with_color "delete line from yaml"
    delete_line $TEST_FILE "MAGENTO_RUN_MODE=developer"
    check_yml_test_file

    print_with_color "append new node"
    yq_append_node $TEST_FILE "services.web.immage" "nginx"
    check_yml_test_file
    # end of yml test

    #test_insert_config

    #test_modify_config_value

    #test_config
    #test_params_assignment
    #test_background
    #check_params "test" 1
    #test_execution
    #test_run_cmd
}

execute run_tests $@
