#!/usr/bin/env bash
source "${MBF_HOME:-$(dirname "$(command -v mbf)")/..}/framework.sh"
mbf::use log args exec

USAGE="Usage: $(basename "$0") [options]"
mbf::args::flag "v" "verbose" "MBF_DEBUG" "Enable debug logging"

function main() {
    mbf::args::parse "$@" || return 1
    mbf::log::info "Starting $(basename "$0")..."
}

main "$@"
