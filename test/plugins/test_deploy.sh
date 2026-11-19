#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test_helper.sh"
source "${MBF_HOME}/framework.sh"
mbf::use deploy ssh exec

# Local-passthrough `ssh` mock: executes the remote command locally against temp dirs
# so we test real release layout, locks, shared symlinks, atomic swap, rollback & cleanup.
function _install_deploy_ssh_stub() {
    cat <<EOF > "${MBF_MOCK_BIN}/ssh"
#!/usr/bin/env bash
printf 'ssh %s\n' "\$*" >> "${MBF_MOCK_LOG}"
last="\${!#}"
bash -c "\$last"
EOF
    chmod +x "${MBF_MOCK_BIN}/ssh"
}

function test_deploy_full_lifecycle_shared_symlink_rollback_and_cleanup() {
    local work_dir deploy_path
    mbf::exec::tmpdir work_dir
    deploy_path="${work_dir}/app"

    _install_deploy_ssh_stub

    # 1. Setup & Lock (including concurrent lock rejection)
    mbf::deploy::setup "deploy@web-01" "$deploy_path"
    assert_eq "yes" "$([ -d "${deploy_path}/releases" ] && echo yes || echo no)"
    assert_eq "yes" "$([ -d "${deploy_path}/shared" ] && echo yes || echo no)"

    mbf::deploy::lock "deploy@web-01" "$deploy_path" "ci-bot@runner"
    local lock_rc=0
    mbf::deploy::lock "deploy@web-01" "$deploy_path" "other-user" >/dev/null 2>&1 || lock_rc=$?
    assert_eq "1" "$lock_rc" "Second concurrent deploy lock must fail"
    mbf::deploy::unlock "deploy@web-01" "$deploy_path"

    # 2. Configure shared files/dirs & writable dirs
    MBF_DEPLOY_SHARED_DIRS=("var/log")
    MBF_DEPLOY_SHARED_FILES=(".env")
    MBF_DEPLOY_WRITABLE_DIRS=("var/cache")

    # Release 1
    local rel1
    rel1="$(mbf::deploy::prepare "deploy@web-01" "$deploy_path" "20261119_100000")"
    assert_eq "${deploy_path}/releases/20261119_100000" "$rel1"
    printf 'v1\n' > "${rel1}/VERSION"
    printf 'DB_HOST=prod-db\n' > "${rel1}/.env"

    mbf::deploy::shared   "deploy@web-01" "$deploy_path" "$rel1"
    mbf::deploy::writable "deploy@web-01" "$rel1"
    mbf::deploy::symlink  "deploy@web-01" "$deploy_path" "$rel1"

    assert_file_exists "${deploy_path}/shared/.env"
    assert_eq "DB_HOST=prod-db" "$(cat "${deploy_path}/current/.env")"
    assert_eq "v1" "$(cat "${deploy_path}/current/VERSION")"
    assert_eq "yes" "$([ -d "${rel1}/var/cache" ] && echo yes || echo no)"

    # Release 2 (shared .env persists from shared/, even if release 2 has no .env)
    local rel2
    rel2="$(mbf::deploy::prepare "deploy@web-01" "$deploy_path" "20261119_110000")"
    printf 'v2\n' > "${rel2}/VERSION"
    mbf::deploy::shared  "deploy@web-01" "$deploy_path" "$rel2"
    mbf::deploy::symlink "deploy@web-01" "$deploy_path" "$rel2"
    assert_eq "v2" "$(cat "${deploy_path}/current/VERSION")"
    assert_eq "DB_HOST=prod-db" "$(cat "${deploy_path}/current/.env")"

    # Release 3
    local rel3
    rel3="$(mbf::deploy::prepare "deploy@web-01" "$deploy_path" "20261119_120000")"
    printf 'v3\n' > "${rel3}/VERSION"
    mbf::deploy::symlink "deploy@web-01" "$deploy_path" "$rel3"
    assert_eq "v3" "$(cat "${deploy_path}/current/VERSION")"

    # Releases list marks active release
    local rel_list
    rel_list="$(mbf::deploy::releases "deploy@web-01" "$deploy_path")"
    assert_contains "$rel_list" "* 20261119_120000 (current)"
    assert_contains "$rel_list" "  20261119_110000"

    # Rollback to previous release (v2)
    local rb_target
    rb_target="$(mbf::deploy::rollback "deploy@web-01" "$deploy_path")"
    assert_eq "$rel2" "$rb_target"
    assert_eq "v2" "$(cat "${deploy_path}/current/VERSION")"

    # Cleanup keep=1 must delete oldest (v1), keep newest (v3), AND protect active rolled-back (v2)!
    mbf::deploy::cleanup "deploy@web-01" "$deploy_path" 1
    assert_eq "no"  "$([ -d "$rel1" ] && echo yes || echo no)" "Oldest release should be pruned"
    assert_eq "yes" "$([ -d "$rel2" ] && echo yes || echo no)" "Active rolled-back release MUST be protected"
    assert_eq "yes" "$([ -d "$rel3" ] && echo yes || echo no)" "Latest release within keep count should remain"
}

function test_deploy_fetch_git_upload_release_and_dryrun() {
    local work_dir build_dir
    mbf::exec::tmpdir work_dir
    build_dir="${work_dir}/dist"
    mkdir -p "$build_dir"

    mock_cmd "ssh" 0
    mock_cmd "rsync" 0

    mbf::deploy::fetch_git "deploy@web-01" "/var/www/app/releases/r1" "git@github.com:acme/app.git" "v2.0.0"
    assert_called_with "ssh" "git clone --depth 1 --branch v2.0.0"

    mbf::deploy::upload_release "deploy@web-01" "$build_dir" "/var/www/app/releases/r1" --exclude="tests"
    assert_called_with "rsync" "deploy@web-01:/var/www/app/releases/r1/"

    # Dry-run should not invoke ssh
    : > "$MBF_MOCK_LOG"
    MBF_DRYRUN="1"
    local dry_rel
    dry_rel="$(mbf::deploy::prepare "deploy@web-01" "/var/www/app" "20261119_999999" 2>/dev/null)"
    assert_eq "/var/www/app/releases/20261119_999999" "$dry_rel"
    mbf::deploy::lock    "deploy@web-01" "/var/www/app" >/dev/null
    mbf::deploy::symlink "deploy@web-01" "/var/www/app" "$dry_rel" >/dev/null
    mbf::deploy::cleanup "deploy@web-01" "/var/www/app" 5 >/dev/null
    mbf::deploy::rollback "deploy@web-01" "/var/www/app" >/dev/null
    MBF_DRYRUN="0"
    assert_not_called_with "ssh"
}

run_test_suite "Plugin: Atomic Remote Deployment (plugins/deploy.sh)"
