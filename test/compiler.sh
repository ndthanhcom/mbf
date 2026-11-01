#!/bin/bash
# script directory. dont use DIR because it's being used by the framework
DIR="${BASH_SOURCE%/*}"
source $DIR/../framework.sh
source $DIR/include.sh

print_with_color "test_compile.sh" "cyan"
