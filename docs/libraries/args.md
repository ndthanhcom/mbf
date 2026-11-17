# Library: `args` `[••••]` — Declarative CLI Arguments & Auto `--help`

`lib/args.sh` eliminates boilerplate `while getopts` / `case` loops. You declare your script's boolean flags and key-value options at the top of the file, and `mbf::args::parse "$@"` handles short flags (`-v`), long flags (`--verbose`), space-separated options (`-e prod`, `--env prod`), equals-separated options (`--env=prod`), the `--` end-of-options marker, and automatic `-h | --help` generation.

---

## Global Variables

- `USAGE` — Optional custom usage header printed at the top of `--help`.
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

### 2. `mbf::args::option <short> <long> <VAR_NAME> <description> [default_value]`
Registers a CLI option that requires a value (`<val>`). Initializes `<VAR_NAME>` to `[default_value]` if provided. Supports `-e val`, `--env val`, and `--env=val`.

```bash
mbf::use args

# Option with a default value ("staging")
mbf::args::option "e" "env"    "OPT_ENV"    "Target environment (dev|staging|prod)" "staging"

# Required option (no default value; check after parsing)
mbf::args::option "d" "domain" "OPT_DOMAIN" "Primary domain name"
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
Prints the formatted `USAGE` banner and aligned options table to `stdout`. Use this when you want to display help manually (for example, when a required positional argument is missing).

```bash
if [ "${#MBF_POSITIONAL_ARGS[@]}" -eq 0 ]; then
    mbf::log::error "Missing <release_tag> argument."
    mbf::args::help
    exit 1
fi
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
