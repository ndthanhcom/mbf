#!/usr/bin/env bash
source "$(mbf --init)"
mbf::strict
export MBF_LOG_STDERR=1
mbf::use log args exec

USAGE="Usage: $(basename "$0") [options]"
mbf::args::flag "n" "dry-run" "MBF_DRYRUN" "Preview changes without modifying system state"
mbf::args::flag "v" "verbose" "MBF_DEBUG"  "Enable debug logging"

function main() {
    mbf::args::parse "$@" || return 1
    mbf::log::info "Starting $(basename "$0")..."
}

main "$@"
