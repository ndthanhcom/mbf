# Core Loader & Framework Predicates (`framework.sh`)

`framework.sh` is the entry point of **mbf (Micro Bash Framework)**. Every `mbf` script begins by sourcing `framework.sh`, which verifies that Bash 4.0+ is running, initializes framework paths, loads `lib/log.sh` automatically, and provides the module loader (`mbf::use`) and execution mode helpers.

---

## Sourcing `framework.sh`

```bash
#!/usr/bin/env bash
# Recommended when `mbf` is in your PATH:
source "$(mbf --init)"

# Alternative when running from a custom path or CI variable:
source "${MBF_HOME:-$HOME/.mbf}/framework.sh"
```

---

## Environment Variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `MBF_HOME` | Auto-detected | Root directory of the `mbf` installation (`~/.mbf`). |
| `MBF_SCRIPT_DIR` | Caller script directory | Absolute directory of the script that sourced `framework.sh`. |
| `MBF_EXT_PATH` | *(empty)* | Colon-separated list of custom extension directories searched before `$MBF_HOME`. |
| `MBF_DRYRUN` | `0` | Set to `1` to simulate commands and file edits without modifying the system. |
| `MBF_SUDO` | `0` | Set to `1` before calling `mbf::init` to pre-authenticate `sudo -v`. |
| `MBF_NO_UPDATE_CHECK` | `0` | Set to `1` to disable the monthly interactive version check. |

---

## Function Reference & Examples

### 1. `mbf::use <module...>`
Loads one or more core libraries, plugins, or custom extensions. Automatically resolves transitive `# mbf:requires` dependencies and skips modules that are already loaded.

```bash
# Load built-in libraries and plugins
mbf::use log args exec config security

# Load a custom extension from ./plugins/magento.sh or MBF_EXT_PATH
mbf::use magento
```

### 2. `mbf::is_loaded <module>`
Returns `0` (true) if `<module>` has already been loaded in the current shell, or `1` (false) otherwise.

```bash
if mbf::is_loaded "notify"; then
    mbf::notify::alert "Deploy Complete" "Release v2.4 is live"
fi
```

### 3. `mbf::strict`
Enables strict execution mode (`set -Eeuo pipefail`) and installs an `ERR` trap that logs the exact file name, line number, failing command, and exit status whenever an unhandled error occurs.

```bash
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::strict

# If `false` or any unchecked command fails below, mbf logs:
# [ERROR] Error in deploy.sh:12 — 'false' exited with status 1
```

### 4. `mbf::init`
Runs optional framework initialization. When `MBF_SUDO=1` is set, it loads `exec` and runs `mbf::exec::init_sudo` (`sudo -v`) upfront so the script does not pause for a password mid-execution.

```bash
MBF_SUDO=1
mbf::init
```

### 5. `mbf::is_dryrun`
Returns `0` (true) when `MBF_DRYRUN=1` is active. Use this inside custom functions before performing direct file writes or destructive actions.

```bash
function deploy_release_symlink() {
    local release_dir="$1"
    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would point /var/www/current -> ${release_dir}"
        return 0
    fi
    ln -sfn "$release_dir" /var/www/current
}
```

### 6. `mbf::in_list <needle> <item1> [item2...]`
Returns `0` (true) if `<needle>` exactly matches any of the remaining arguments.

```bash
allowed_envs=("dev" "staging" "production")

if ! mbf::in_list "$OPT_ENV" "${allowed_envs[@]}"; then
    mbf::die "Invalid environment '${OPT_ENV}'. Allowed: ${allowed_envs[*]}"
fi
```

### 7. `mbf::version`
Prints the current `mbf` semantic version string (e.g., `1.0.0`).

```bash
printf 'Running on mbf v%s\n' "$(mbf::version)"
```

### 8. `mbf::check_update [--force]`
Checks at most once every 30 days (cached in `$MBF_HOME/.version_check`) whether a newer version of `mbf` is available on GitHub. Automatically skipped in non-interactive shells, CI, dry-run mode, and exported scripts. Pass `--force` to check immediately.

```bash
# Force an immediate check against GitHub
mbf::check_update --force
```

### 9. `mbf::update [branch]`
Updates the local `mbf` installation in `$MBF_HOME` via `git pull --ff-only`.

```bash
# Update to latest default branch
mbf::update

# Update from a specific branch
mbf::update "master"
```
