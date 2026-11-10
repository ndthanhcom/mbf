#!/usr/bin/env bash
# mbf:requires log exec os service
# ==============================================================================
# mbf plugin: docker
# Docker Engine & Docker Compose Stack Deployment and Safe Cleanup
# ==============================================================================

# Ensure Docker Engine and Docker Compose plugin are installed and running
function mbf::docker::ensure_installed() {
    if ! command -v docker >/dev/null 2>&1; then
        mbf::os::pkg_install docker.io docker-compose-plugin || mbf::os::pkg_install docker || return 1
    fi
    mbf::service::ensure_running docker
}

# Deploy or update a Docker Compose stack in `<project_dir>`
# Usage: mbf::docker::compose_up <project_dir> [compose_file]
function mbf::docker::compose_up() {
    local proj_dir="$1"
    local compose_file="${2:-docker-compose.yml}"

    if [ ! -f "${proj_dir}/${compose_file}" ]; then
        mbf::log::error "mbf::docker::compose_up: ${proj_dir}/${compose_file} not found"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would run docker compose up -d in $proj_dir ($compose_file)"
        return 0
    fi

    if docker compose version >/dev/null 2>&1; then
        mbf::exec::run docker compose -f "${proj_dir}/${compose_file}" --project-directory "$proj_dir" up -d --remove-orphans
    else
        mbf::exec::run docker-compose -f "${proj_dir}/${compose_file}" up -d --remove-orphans
    fi
}

# Stop and remove containers for a Docker Compose stack in `<project_dir>`
function mbf::docker::compose_down() {
    local proj_dir="$1"
    local compose_file="${2:-docker-compose.yml}"

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would run docker compose down in $proj_dir"
        return 0
    fi

    if docker compose version >/dev/null 2>&1; then
        mbf::exec::run docker compose -f "${proj_dir}/${compose_file}" --project-directory "$proj_dir" down
    else
        mbf::exec::run docker-compose -f "${proj_dir}/${compose_file}" down
    fi
}

# Prune dangling images, stopped containers, and unused networks safely
function mbf::docker::prune_safe() {
    mbf::exec::run docker system prune -f
}
