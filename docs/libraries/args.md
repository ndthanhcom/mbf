# Library: `args` — Declarative CLI Arguments & Auto `--help`

`lib/args.sh` eliminates boilerplate `while getopts` / `case` loops. You declare your script's boolean flags, single options, and repeatable array options at the top of the file, and `mbf::args::parse "$@"` handles short flags (`-v`), combined short flags (`-nv`), long flags (`--verbose`, `--no-verbose`), space-separated options (`-e prod`, `--env prod`), equals-separated options (`--env=prod`), env-var fallbacks, the `--` end-of-options marker, and automatic `-h | --help` generation.

---

## Global Variables

- `MBF_USAGE` (or `USAGE`) — Optional custom usage header printed at the top of `--help`.
- `MBF_POSITIONAL_ARGS` — Array populated with all non-option positional arguments after `mbf::args::parse "$@"` runs.
- `MBF_ARGS_NO_EXIT=1` — Optional flag to make `-h | --help` return `0` instead of calling `exit 0`.

---

## Function Reference & Examples

### 1. `mbf::args::flag <short> <long> <VAR_NAME> <description>`
Registers a boolean CLI flag. Initializes `<VAR_NAME>` to `"0"` if unset, and sets it to `"1"` when `-<short>` or `--<long>` is passed on the command line.

```bash
mbf::use args

# Sets $MBF_DRYRUN="0" by default, or "1" when `-n` or `--dry-run` is passed
mbf::args::flag "n" "dry-run" "MBF_DRYRUN" "Preview changes without modifying files"

# Sets $MBF_DEBUG="0" by default, or "1" when `-v` or `--verbose` is passed
mbf::args::flag "v" "verbose" "MBF_DEBUG"  "Enable verbose debug logging"
```

### 2. `mbf::args::option <short> <long> <VAR_NAME> <description> [default_value] [env_var]`
Registers a CLI option that requires a value (`<val>`). Initializes `<VAR_NAME>` from `[env_var]` (if set in the environment) or `[default_value]`, and displays `(default: ...)` and `[env: ...]` in `--help`. Supports `-e val`, `--env val`, and `--env=val`.

```bash
mbf::use args

# Option with a default value ("staging") and environment variable fallback ($APP_ENV)
mbf::args::option "e" "env"    "OPT_ENV"    "Target environment (dev|staging|prod)" "staging" "APP_ENV"

# Required option (no default value; check with mbf::args::require after parsing)
mbf::args::option "d" "domain" "OPT_DOMAIN" "Primary domain name"
```

### 2b. `mbf::args::multi <short> <long> <ARRAY_VAR> <description>`
Registers a repeatable CLI option whose values are appended into `<ARRAY_VAR>` (displayed as `(repeatable)` in `--help`). Supports `-H val`, `--host val`, and `--host=val`.

```bash
mbf::args::multi "H" "host" "OPT_HOSTS" "Target host"
mbf::args::parse -H web01 --host web02 --host=web03
printf '%s\n' "${OPT_HOSTS[@]}"
```

### 3. `mbf::args::parse "$@"`
Parses all command-line arguments:
- Populates registered flag and option variables.
- Stores remaining positional arguments in `MBF_POSITIONAL_ARGS=()`.
- Treats everything after `--` as positional arguments.
- If `-h` or `--help` is passed, prints the help table and exits `0`.
- If an unknown flag or option with a missing value is passed, logs an error, prints help to `stderr`, and returns `1`.

```bash
mbf::args::parse "$@" || exit 1

# Access parsed options and positional arguments:
echo "Environment : ${OPT_ENV}"
echo "First target: ${MBF_POSITIONAL_ARGS[0]:-none}"
```

### 4. `mbf::args::help`
Prints the formatted `USAGE` banner, registered `Commands:`, and aligned `Options:` table to `stdout`.

### 5. `mbf::args::require <VAR_NAME> [label]`
Validates that `<VAR_NAME>` is set and non-empty after `mbf::args::parse`, logging an error and printing `--help` to stderr if missing. Registered boolean flags also automatically support `--no-<long>` negation.

```bash
mbf::args::option "d" "domain" "OPT_DOMAIN" "Application domain"
mbf::args::parse "$@" || exit 1
mbf::args::require OPT_DOMAIN "--domain" || exit 1
```

### 6. `mbf::args::command <name> <description>`, `dispatch <fn_prefix> "$@"`, & `mbf::args::reset [usage]`
Registers subcommands (displayed under `Commands:` in `--help`) and dispatches `<subcommand>` to `<fn_prefix>_<subcommand>`. Call `mbf::args::reset [new_usage]` inside a subcommand handler to clear previously registered flags/commands and define subcommand-specific options and `--help`.

```bash
mbf::args::command "deploy"   "Deploy latest release"
mbf::args::command "rollback" "Roll back to previous release"

function cmd_deploy() {
    mbf::args::reset "Usage: myctl deploy [options]"
    mbf::args::option "b" "branch" "OPT_BRANCH" "Git branch" "main"
    mbf::args::parse "$@" || return 1
    mbf::log::info "Deploying branch ${OPT_BRANCH}"
}
function cmd_rollback() { mbf::log::info "Rolling back $*"; }

mbf::args::dispatch "cmd" "$@"
```

---

## Complete Example Script

```bash
#!/usr/bin/env bash
source "$(mbf --init)"
mbf::use log args

USAGE="Usage: deploy.sh [options] <release_tag>"

mbf::args::flag   "n" "dry-run" "MBF_DRYRUN"  "Simulate deployment without making changes"
mbf::args::flag   "v" "verbose" "MBF_DEBUG"   "Enable debug logging"
mbf::args::option "e" "env"     "OPT_ENV"     "Target environment (staging|prod)" "staging"
mbf::args::option "w" "workers" "OPT_WORKERS" "Number of parallel workers" "4"

function main() {
    mbf::args::parse "$@" || return 1

    local release_tag="${MBF_POSITIONAL_ARGS[0]:-}"
    if [ -z "$release_tag" ]; then
        mbf::log::error "<release_tag> is required."
        mbf::args::help >&2
        return 1
    fi

    mbf::log::info "Deploying ${release_tag} to ${OPT_ENV} with ${OPT_WORKERS} workers..."
}

main "$@"
```

Running `./deploy.sh --help` produces:

```text
Usage: deploy.sh [options] <release_tag>

Options:
  -h, --help                Show this help message and exit
  -n, --dry-run             Simulate deployment without making changes
  -v, --verbose             Enable debug logging
  -e, --env <val>           Target environment (staging|prod) (default: staging)
  -w, --workers <val>       Number of parallel workers (default: 4)
```
