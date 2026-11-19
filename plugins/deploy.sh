#!/usr/bin/env bash
# @mbf-module: deploy
# mbf:requires log exec ssh
# ==============================================================================
# mbf plugin: deploy
# Capistrano / Deployer.php-style atomic zero-downtime release management over SSH
#
# Remote Directory Layout:
#   <deploy_path>/
#   ├── current -> releases/<release_id>   # Atomic symlink swap (`mv -Tf`)
#   ├── releases/<release_id>/             # Immutable timestamped releases
#   ├── shared/                            # Persistent shared dirs & files
#   └── .dep/
#       ├── deploy.lock/                   # Atomic mkdir concurrency lock
#       └── releases.log                   # Deployment & rollback history
#
# Configuration Variables:
#   MBF_DEPLOY_SHARED_DIRS    : Array of relative dir paths persisted in `shared/`
#   MBF_DEPLOY_SHARED_FILES   : Array of relative file paths persisted in `shared/`
#   MBF_DEPLOY_WRITABLE_DIRS  : Array of relative dir paths to chmod in new release
#   MBF_DEPLOY_WRITABLE_MODE  : Chmod mode for writable dirs (default: 0775)
#   MBF_DEPLOY_KEEP_RELEASES  : Number of releases to retain in cleanup (default: 5)
# ==============================================================================

# mbf:state_start
MBF_DEPLOY_SHARED_DIRS=()
MBF_DEPLOY_SHARED_FILES=()
MBF_DEPLOY_WRITABLE_DIRS=()
MBF_DEPLOY_WRITABLE_MODE="${MBF_DEPLOY_WRITABLE_MODE:-0775}"
MBF_DEPLOY_KEEP_RELEASES="${MBF_DEPLOY_KEEP_RELEASES:-5}"
# mbf:state_end

# Initialize the remote deployment directory layout (`releases/`, `shared/`, `.dep/`)
# Usage: mbf::deploy::setup <host> <deploy_path>
function mbf::deploy::setup() {
    local host="${1:-}"
    local deploy_path="${2:-}"
    if [ -z "$host" ] || [ -z "$deploy_path" ]; then
        mbf::log::error "mbf::deploy::setup: <host> and <deploy_path> are required"
        return 1
    fi

    mbf::ssh::run "$host" mkdir -p "${deploy_path}/releases" "${deploy_path}/shared" "${deploy_path}/.dep"
}

# Acquire an atomic remote deployment lock (auto-unlocks on shell exit via `on_exit`)
# Usage: mbf::deploy::lock <host> <deploy_path> [deployer_info]
function mbf::deploy::lock() {
    local host="${1:-}"
    local deploy_path="${2:-}"
    local who="${3:-}"
    [ -n "$who" ] || who="${USER:-unknown}@$(hostname 2>/dev/null || echo local)"

    if [ -z "$host" ] || [ -z "$deploy_path" ]; then
        mbf::log::error "mbf::deploy::lock: <host> and <deploy_path> are required"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] [deploy:${host}] Would acquire lock in ${deploy_path}/.dep/deploy.lock"
        return 0
    fi

    local lock_script='
set -eu
deploy_path="$1"
who="$2"
lock_dir="${deploy_path}/.dep/deploy.lock"
mkdir -p "${deploy_path}/.dep"
if ! mkdir "$lock_dir" 2>/dev/null; then
    holder="unknown"
    [ -r "${lock_dir}/info" ] && holder="$(cat "${lock_dir}/info")"
    printf "Deployment already locked by: %s\n" "$holder" >&2
    exit 1
fi
printf "%s (%s)\n" "$who" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "${lock_dir}/info"
'
    mbf::ssh::run_bash "$host" "$lock_script" "$deploy_path" "$who" || return 1

    local q_host q_path
    printf -v q_host '%q' "$host"
    printf -v q_path '%q' "$deploy_path"
    mbf::exec::on_exit "mbf::deploy::unlock ${q_host} ${q_path}"
    return 0
}

# Release the remote deployment lock explicitly
# Usage: mbf::deploy::unlock <host> <deploy_path>
function mbf::deploy::unlock() {
    local host="${1:-}"
    local deploy_path="${2:-}"
    [ -n "$host" ] && [ -n "$deploy_path" ] || return 0
    mbf::is_dryrun && return 0

    mbf::ssh::run "$host" rm -rf "${deploy_path}/.dep/deploy.lock" >/dev/null 2>&1 || true
    return 0
}

# Create a new timestamped release directory and print its full path to stdout
# Usage: release_path="$(mbf::deploy::prepare <host> <deploy_path> [release_id])"
function mbf::deploy::prepare() {
    local host="${1:-}"
    local deploy_path="${2:-}"
    local release_id="${3:-}"
    [ -n "$release_id" ] || release_id="$(date -u +'%Y%m%d_%H%M%S')"

    if [ -z "$host" ] || [ -z "$deploy_path" ]; then
        mbf::log::error "mbf::deploy::prepare: <host> and <deploy_path> are required"
        return 1
    fi

    local release_path="${deploy_path}/releases/${release_id}"
    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] [deploy:${host}] Would prepare release directory ${release_path}" >&2
        printf '%s\n' "$release_path"
        return 0
    fi

    mbf::ssh::run "$host" mkdir -p "$release_path" || return 1
    printf '%s\n' "$release_path"
}

# Populate `<release_path>` on `<host>` via a shallow Git clone
# Usage: mbf::deploy::fetch_git <host> <release_path> <repo_url> [branch_or_tag]
function mbf::deploy::fetch_git() {
    local host="${1:-}"
    local release_path="${2:-}"
    local repo_url="${3:-}"
    local branch="${4:-main}"

    if [ -z "$host" ] || [ -z "$release_path" ] || [ -z "$repo_url" ]; then
        mbf::log::error "mbf::deploy::fetch_git: <host>, <release_path>, and <repo_url> are required"
        return 1
    fi

    mbf::ssh::run "$host" git clone --depth 1 --branch "$branch" "$repo_url" "$release_path"
}

# Populate `<release_path>` on `<host>` by syncing a pre-built local directory (CI artifact)
# Usage: mbf::deploy::upload_release <host> <local_dir> <release_path> [extra_rsync_args...]
function mbf::deploy::upload_release() {
    local host="${1:-}"
    local local_dir="${2:-}"
    local release_path="${3:-}"
    shift 3 2>/dev/null || true

    if [ -z "$host" ] || [ -z "$local_dir" ] || [ -z "$release_path" ]; then
        mbf::log::error "mbf::deploy::upload_release: <host>, <local_dir>, and <release_path> are required"
        return 1
    fi

    mbf::ssh::sync "$host" "$local_dir" "$release_path" "$@"
}

# Symlink `MBF_DEPLOY_SHARED_DIRS` and `MBF_DEPLOY_SHARED_FILES` from `shared/` into `<release_path>`
# Usage: mbf::deploy::shared <host> <deploy_path> <release_path>
function mbf::deploy::shared() {
    local host="${1:-}"
    local deploy_path="${2:-}"
    local release_path="${3:-}"

    if [ -z "$host" ] || [ -z "$deploy_path" ] || [ -z "$release_path" ]; then
        mbf::log::error "mbf::deploy::shared: <host>, <deploy_path>, and <release_path> are required"
        return 1
    fi

    local dir_count="${#MBF_DEPLOY_SHARED_DIRS[@]}"
    local file_count="${#MBF_DEPLOY_SHARED_FILES[@]}"
    if [ "$dir_count" -eq 0 ] && [ "$file_count" -eq 0 ]; then
        return 0
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] [deploy:${host}] Would link ${dir_count} shared dir(s) and ${file_count} shared file(s) into ${release_path}"
        return 0
    fi

    local shared_script='
set -eu
deploy_path="$1"
release_path="$2"
dir_count="$3"
shift 3

i=0
while [ "$i" -lt "$dir_count" ]; do
    rel="$1"
    shift
    i=$((i + 1))
    [ -n "$rel" ] || continue
    shared_target="${deploy_path}/shared/${rel}"
    release_target="${release_path}/${rel}"
    if [ ! -d "$shared_target" ]; then
        mkdir -p "$shared_target"
        if [ -d "$release_target" ] && [ ! -L "$release_target" ]; then
            cp -R "${release_target}/." "$shared_target/" 2>/dev/null || true
        fi
    fi
    rm -rf "$release_target"
    mkdir -p "$(dirname "$release_target")"
    ln -s "$shared_target" "$release_target"
done

for rel in "$@"; do
    [ -n "$rel" ] || continue
    shared_target="${deploy_path}/shared/${rel}"
    release_target="${release_path}/${rel}"
    mkdir -p "$(dirname "$shared_target")"
    if [ ! -f "$shared_target" ]; then
        if [ -f "$release_target" ] && [ ! -L "$release_target" ]; then
            cp -p "$release_target" "$shared_target"
        else
            touch "$shared_target"
        fi
    fi
    rm -f "$release_target"
    mkdir -p "$(dirname "$release_target")"
    ln -s "$shared_target" "$release_target"
done
'
    mbf::ssh::run_bash "$host" "$shared_script" "$deploy_path" "$release_path" "$dir_count" \
        ${MBF_DEPLOY_SHARED_DIRS[@]+"${MBF_DEPLOY_SHARED_DIRS[@]}"} \
        ${MBF_DEPLOY_SHARED_FILES[@]+"${MBF_DEPLOY_SHARED_FILES[@]}"}
}

# Ensure `MBF_DEPLOY_WRITABLE_DIRS` exist and apply writable permissions in `<release_path>`
# Usage: mbf::deploy::writable <host> <release_path> [mode]
function mbf::deploy::writable() {
    local host="${1:-}"
    local release_path="${2:-}"
    local mode="${3:-${MBF_DEPLOY_WRITABLE_MODE:-0775}}"

    if [ -z "$host" ] || [ -z "$release_path" ]; then
        mbf::log::error "mbf::deploy::writable: <host> and <release_path> are required"
        return 1
    fi

    if [ "${#MBF_DEPLOY_WRITABLE_DIRS[@]}" -eq 0 ]; then
        return 0
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] [deploy:${host}] Would chmod ${mode} on ${#MBF_DEPLOY_WRITABLE_DIRS[@]} writable dir(s)"
        return 0
    fi

    local writable_script='
set -eu
release_path="$1"
mode="$2"
shift 2
for rel in "$@"; do
    [ -n "$rel" ] || continue
    target="${release_path}/${rel}"
    mkdir -p "$target"
    chmod -R "$mode" "$target"
done
'
    mbf::ssh::run_bash "$host" "$writable_script" "$release_path" "$mode" "${MBF_DEPLOY_WRITABLE_DIRS[@]}"
}

# Atomically switch `<deploy_path>/current` symlink to `<release_path>` and log release metadata
# Uses `ln -s` + `mv -Tf` (POSIX `rename(2)`) when supported for zero-downtime swap.
# Usage: mbf::deploy::symlink <host> <deploy_path> <release_path>
function mbf::deploy::symlink() {
    local host="${1:-}"
    local deploy_path="${2:-}"
    local release_path="${3:-}"

    if [ -z "$host" ] || [ -z "$deploy_path" ] || [ -z "$release_path" ]; then
        mbf::log::error "mbf::deploy::symlink: <host>, <deploy_path>, and <release_path> are required"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] [deploy:${host}] Would atomically link ${deploy_path}/current -> ${release_path}"
        return 0
    fi

    local symlink_script='
set -eu
deploy_path="$1"
release_path="$2"
rel_id="$(basename "$release_path")"
tmp_link="${deploy_path}/.current.tmp.$$"

rm -rf "$tmp_link"
ln -s "$release_path" "$tmp_link"
if mv -Tf "$tmp_link" "${deploy_path}/current" 2>/dev/null; then
    :
else
    rm -rf "$tmp_link"
    if [ -d "${deploy_path}/current" ] && [ ! -L "${deploy_path}/current" ]; then
        rm -rf "${deploy_path}/current"
        ln -s "$release_path" "${deploy_path}/current"
    else
        ln -sfn "$release_path" "${deploy_path}/current"
    fi
fi

mkdir -p "${deploy_path}/.dep"
printf "%s\n" "$rel_id" > "${deploy_path}/.dep/current_release"
printf "%s deploy %s\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$rel_id" >> "${deploy_path}/.dep/releases.log"
'
    mbf::ssh::run_bash "$host" "$symlink_script" "$deploy_path" "$release_path"
}

# Prune old releases beyond `<keep_releases>`, always protecting the active `current` target
# Usage: mbf::deploy::cleanup <host> <deploy_path> [keep_releases]
function mbf::deploy::cleanup() {
    local host="${1:-}"
    local deploy_path="${2:-}"
    local keep="${3:-${MBF_DEPLOY_KEEP_RELEASES:-5}}"

    if [ -z "$host" ] || [ -z "$deploy_path" ]; then
        mbf::log::error "mbf::deploy::cleanup: <host> and <deploy_path> are required"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] [deploy:${host}] Would keep latest ${keep} release(s) in ${deploy_path}/releases"
        return 0
    fi

    local cleanup_script='
set -eu
deploy_path="$1"
keep="$2"
releases_dir="${deploy_path}/releases"
[ -d "$releases_dir" ] || exit 0

active_id=""
if [ -L "${deploy_path}/current" ]; then
    active_target="$(readlink "${deploy_path}/current" 2>/dev/null || true)"
    [ -n "$active_target" ] && active_id="$(basename "$active_target")"
elif [ -r "${deploy_path}/.dep/current_release" ]; then
    active_id="$(cat "${deploy_path}/.dep/current_release" 2>/dev/null || true)"
fi

count=0
for rel in $(ls -1r "$releases_dir" 2>/dev/null); do
    [ -d "${releases_dir}/${rel}" ] || continue
    count=$((count + 1))
    if [ "$count" -gt "$keep" ] && [ "$rel" != "$active_id" ]; then
        rm -rf "${releases_dir:?}/${rel}"
    fi
done
'
    mbf::ssh::run_bash "$host" "$cleanup_script" "$deploy_path" "$keep"
}

# Atomically roll back `<deploy_path>/current` to the previous release (or `<target_release_id>`)
# Usage: mbf::deploy::rollback <host> <deploy_path> [target_release_id]
function mbf::deploy::rollback() {
    local host="${1:-}"
    local deploy_path="${2:-}"
    local target_id="${3:-}"

    if [ -z "$host" ] || [ -z "$deploy_path" ]; then
        mbf::log::error "mbf::deploy::rollback: <host> and <deploy_path> are required"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] [deploy:${host}] Would roll back ${deploy_path}/current${target_id:+ to ${target_id}}"
        return 0
    fi

    local rollback_script='
set -eu
deploy_path="$1"
target_id="${2:-}"
releases_dir="${deploy_path}/releases"

active_id=""
if [ -L "${deploy_path}/current" ]; then
    active_target="$(readlink "${deploy_path}/current" 2>/dev/null || true)"
    [ -n "$active_target" ] && active_id="$(basename "$active_target")"
elif [ -r "${deploy_path}/.dep/current_release" ]; then
    active_id="$(cat "${deploy_path}/.dep/current_release" 2>/dev/null || true)"
fi

if [ -z "$target_id" ]; then
    for rel in $(ls -1r "$releases_dir" 2>/dev/null); do
        [ -d "${releases_dir}/${rel}" ] || continue
        if [ "$rel" != "$active_id" ]; then
            target_id="$rel"
            break
        fi
    done
fi

if [ -z "$target_id" ] || [ ! -d "${releases_dir}/${target_id}" ]; then
    printf "No previous release available to roll back to in %s\n" "$releases_dir" >&2
    exit 1
fi

target_path="${releases_dir}/${target_id}"
tmp_link="${deploy_path}/.current.tmp.$$"
rm -rf "$tmp_link"
ln -s "$target_path" "$tmp_link"
if mv -Tf "$tmp_link" "${deploy_path}/current" 2>/dev/null; then
    :
else
    rm -rf "$tmp_link"
    if [ -d "${deploy_path}/current" ] && [ ! -L "${deploy_path}/current" ]; then
        rm -rf "${deploy_path}/current"
        ln -s "$target_path" "${deploy_path}/current"
    else
        ln -sfn "$target_path" "${deploy_path}/current"
    fi
fi

mkdir -p "${deploy_path}/.dep"
printf "%s\n" "$target_id" > "${deploy_path}/.dep/current_release"
printf "%s rollback %s\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$target_id" >> "${deploy_path}/.dep/releases.log"
printf "%s\n" "$target_path"
'
    mbf::ssh::run_bash "$host" "$rollback_script" "$deploy_path" "$target_id"
}

# List available releases on `<host>`, marking the currently active release with `*`
# Usage: mbf::deploy::releases <host> <deploy_path>
function mbf::deploy::releases() {
    local host="${1:-}"
    local deploy_path="${2:-}"

    if [ -z "$host" ] || [ -z "$deploy_path" ]; then
        mbf::log::error "mbf::deploy::releases: <host> and <deploy_path> are required"
        return 1
    fi

    local list_script='
set -eu
deploy_path="$1"
releases_dir="${deploy_path}/releases"
[ -d "$releases_dir" ] || exit 0

active_id=""
if [ -L "${deploy_path}/current" ]; then
    active_target="$(readlink "${deploy_path}/current" 2>/dev/null || true)"
    [ -n "$active_target" ] && active_id="$(basename "$active_target")"
elif [ -r "${deploy_path}/.dep/current_release" ]; then
    active_id="$(cat "${deploy_path}/.dep/current_release" 2>/dev/null || true)"
fi

for rel in $(ls -1r "$releases_dir" 2>/dev/null); do
    [ -d "${releases_dir}/${rel}" ] || continue
    if [ "$rel" == "$active_id" ]; then
        printf "* %s (current)\n" "$rel"
    else
        printf "  %s\n" "$rel"
    fi
done
'
    mbf::ssh::run_bash "$host" "$list_script" "$deploy_path"
}
