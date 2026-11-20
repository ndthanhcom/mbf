# Plugin: `deploy`

> **Source**: `plugins/deploy.sh` | **Dependencies**: `log`, `exec`, `ssh`
> **Load**: `mbf::use deploy`

Capistrano / Deployer.php-style atomic zero-downtime release management over SSH.

---

## Remote Directory Layout

```text
/var/www/myapp/
├── current -> releases/20261119_162000   # Atomic symlink swap (`mv -Tf`)
├── releases/
│   ├── 20261118_100000/
│   └── 20261119_162000/
├── shared/                               # Persistent dirs & files across releases
│   ├── .env
│   └── var/log/
└── .dep/
    ├── deploy.lock/                      # Atomic mkdir concurrency lock
    └── releases.log                      # Deploy & rollback audit log
```

---

## Configuration Variables

| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `MBF_DEPLOY_SHARED_DIRS` | `()` | Array of relative directory paths persisted in `shared/` |
| `MBF_DEPLOY_SHARED_FILES` | `()` | Array of relative file paths persisted in `shared/` |
| `MBF_DEPLOY_WRITABLE_DIRS` | `()` | Array of relative directory paths to `chmod` in new release |
| `MBF_DEPLOY_WRITABLE_MODE` | `0775` | Permissions applied by `mbf::deploy::writable` |
| `MBF_DEPLOY_KEEP_RELEASES` | `5` | Number of recent releases retained by `mbf::deploy::cleanup` |

---

## Function Reference

### `mbf::deploy::setup <host> <deploy_path>`
Idempotently creates `<deploy_path>/{releases,shared,.dep}` on `<host>`.

### `mbf::deploy::lock <host> <deploy_path> [deployer_info]`
Acquires an atomic remote `mkdir` lock at `.dep/deploy.lock` and registers `mbf::deploy::unlock` on shell exit via `mbf::exec::on_exit`. Fails cleanly if another deploy is already in progress.

### `mbf::deploy::unlock <host> <deploy_path>`
Removes `.dep/deploy.lock` on `<host>`.

### `mbf::deploy::prepare <host> <deploy_path> [release_id]`
Creates `<deploy_path>/releases/<release_id>` (defaulting to UTC `YYYYMMDD_HHMMSS`) and prints the full `<release_path>` on stdout.

### `mbf::deploy::fetch_git <host> <release_path> <repo_url> [branch_or_tag]`
Populates `<release_path>` via shallow `git clone --depth 1 --branch <branch>`.

### `mbf::deploy::upload_release <host> <local_dir> <release_path> [extra_rsync_args...]`
Syncs a pre-built local CI artifact directory into `<release_path>` via `mbf::ssh::sync`.

### `mbf::deploy::shared <host> <deploy_path> <release_path>`
Symlinks all entries in `MBF_DEPLOY_SHARED_DIRS` and `MBF_DEPLOY_SHARED_FILES` from `shared/` into `<release_path>`, seeding `shared/` from the release if a target does not yet exist.

### `mbf::deploy::writable <host> <release_path> [mode]`
Creates and applies `chmod -R <mode>` on all directories in `MBF_DEPLOY_WRITABLE_DIRS`.

### `mbf::deploy::symlink <host> <deploy_path> <release_path>`
Atomically switches `<deploy_path>/current` to `<release_path>` (`ln -s` + `mv -Tf`, with `ln -sfn` fallback on BSD/macOS) and appends an entry to `.dep/releases.log`.

### `mbf::deploy::cleanup <host> <deploy_path> [keep_releases]`
Deletes old releases beyond `<keep_releases>` while **never** removing the currently active `current` target (even after a rollback).

### `mbf::deploy::rollback <host> <deploy_path> [target_release_id]`
Atomically switches `<deploy_path>/current` back to the previous older release (never rolling forward on consecutive rollbacks) — or directly to `[target_release_id]` when specified — logs the rollback in `.dep/releases.log`, and prints the restored release path.

### `mbf::deploy::releases <host> <deploy_path>`
Lists releases on `<host>` in reverse chronological order, marking the active release with `* <id> (current)`.

---

## Complete Example

```bash
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::strict
mbf::use log args ssh deploy

HOST="deploy@web-01.example.com"
DEPLOY_PATH="/var/www/shop"
MBF_DEPLOY_SHARED_FILES=(".env")
MBF_DEPLOY_SHARED_DIRS=("var/log" "pub/media")
MBF_DEPLOY_WRITABLE_DIRS=("var/cache")

mbf::args::flag "n" "dry-run"  "MBF_DRYRUN"   "Preview deployment"
mbf::args::flag "r" "rollback" "OPT_ROLLBACK" "Roll back to previous release"
mbf::args::parse "$@" || exit 1

mbf::ssh::open "$HOST"
if [ "$OPT_ROLLBACK" == "1" ]; then
    mbf::deploy::rollback "$HOST" "$DEPLOY_PATH"
    exit 0
fi

mbf::deploy::setup "$HOST" "$DEPLOY_PATH"
mbf::deploy::lock  "$HOST" "$DEPLOY_PATH"
rel="$(mbf::deploy::prepare "$HOST" "$DEPLOY_PATH")"
mbf::deploy::fetch_git "$HOST" "$rel" "git@github.com:acme/shop.git" "main"
mbf::deploy::shared    "$HOST" "$DEPLOY_PATH" "$rel"
mbf::deploy::writable  "$HOST" "$rel"
mbf::deploy::symlink   "$HOST" "$DEPLOY_PATH" "$rel"
mbf::deploy::cleanup   "$HOST" "$DEPLOY_PATH" 5
```
