# Core Library: `ssh`

> **Source**: `lib/ssh.sh` | **Dependencies**: `log`, `exec`
> **Load**: `mbf::use ssh`

Agentless SSH remote execution, `ControlMaster` connection multiplexing, file upload/sync, multi-host execution, and on-the-fly tree-shaken script streaming (`mbf::ssh::exec_script`).

---

## Configuration Environment Variables

| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `MBF_SSH_PORT` | *(empty)* | Custom SSH port (`-p` / `-P`) |
| `MBF_SSH_KEY` | *(empty)* | Path to SSH private key (`-i`) |
| `MBF_SSH_TIMEOUT` | `10` | `ConnectTimeout` in seconds |
| `MBF_SSH_OPTS` | *(empty)* | Extra space-separated SSH options |
| `MBF_SSH_MUX_DIR` | `$TMPDIR/mbf-ssh-mux` | Directory for `ControlMaster` Unix sockets |
| `MBF_SSH_CONTROL_PERSIST` | `60` | Seconds to keep idle multiplexed socket alive |
| `MBF_SSH_PARALLEL` | `0` | Set to `1` to run `mbf::ssh::run_many` concurrently |
| `MBF_SSH_SELF_REMOVE` | `0` | Set to `1` to stage `exec_script` as a `0700` remote temp file that deletes itself on exit/error |

---

## Function Reference

### `mbf::ssh::open <user@host>`
Opens a persistent multiplexed SSH connection (`ControlMaster=yes`) for `<host>` and automatically registers `mbf::ssh::close` on shell exit. Subsequent `run`, `run_bash`, `exec_script`, `upload`, and `sync` calls reuse the single TCP session.

```bash
mbf::ssh::open "deploy@web-01.example.com"
```

### `mbf::ssh::close <user@host>`
Explicitly closes an active multiplexed SSH connection and removes its socket file.

```bash
mbf::ssh::close "deploy@web-01.example.com"
```

### `mbf::ssh::run <user@host> <cmd> [args...]`
Safely shell-quotes every argument (`printf '%q'`) and executes `<cmd>` on `<host>`. Respects `MBF_DRYRUN=1`.

```bash
mbf::ssh::run "deploy@web-01.example.com" sudo systemctl reload nginx
```

### `mbf::ssh::run_bash <user@host> "<bash_code>" [args...]`
Streams a multi-line Bash snippet over `stdin` to `bash -s -- [args...]` on `<host>`, avoiding nested-quote escaping issues.

```bash
mbf::ssh::run_bash "deploy@web-01.example.com" '
set -eu
cd "$1"
git rev-parse --short HEAD
' "/var/www/app/current"
```

### `mbf::ssh::exec_script [--self-remove] <user@host> <local_script.sh> [args...]`
Exports a local MBF script into a tree-shaken standalone `.sh` file (via `mbf export`) and runs it on `<host>`—so **the remote server needs zero `mbf` installation**. Plain Bash scripts are streamed directly.

- **Default**: Streams over SSH stdin (`bash -s`), leaving zero files on disk on the remote server.
- **`--self-remove`** (or `MBF_SSH_SELF_REMOVE=1`): Stages the exported script to a `0700` remote temp file with an injected `EXIT` self-removal trap (`trap 'rm -f -- "${BASH_SOURCE[0]:-$0}"' EXIT`), executes it with a clean stdin (`</dev/null`) and real `$0`/`BASH_SOURCE[0]`, and removes itself immediately on completion or failure.

```bash
mbf::ssh::exec_script "deploy@web-01.example.com" "./scripts/healthcheck.sh" --port 8080
mbf::ssh::exec_script --self-remove "deploy@web-01.example.com" "./scripts/bootstrap.sh"
```

Also available directly from the CLI:
```bash
mbf remote deploy@web-01.example.com ./scripts/healthcheck.sh -- --port 8080
mbf remote --self-remove deploy@web-01.example.com ./scripts/bootstrap.sh
```

### `mbf::ssh::upload <user@host> <local_path> <remote_path>`
Uploads a local file or directory to `<host>:<remote_path>` via `scp` using the configured port, key, and multiplexed socket.

```bash
mbf::ssh::upload "deploy@web-01.example.com" "./dist/app.env" "/var/www/app/shared/.env"
```

### `mbf::ssh::sync <user@host> <local_dir> <remote_dir> [extra_rsync_args...]`
Synchronizes `<local_dir>/` to `<host>:<remote_dir>/` via `rsync -az --delete` over the configured SSH transport.

```bash
mbf::ssh::sync "deploy@web-01.example.com" "./build" "/var/www/app/releases/20261119" --exclude=".git"
```

### `mbf::ssh::run_many <hosts_csv_or_space> <cmd> [args...]`
Executes `<cmd>` across multiple hosts (comma- or space-separated), prefixing every output line with `[host]`. Set `MBF_SSH_PARALLEL=1` for concurrent execution.

```bash
MBF_SSH_PARALLEL=1 mbf::ssh::run_many "deploy@web-01,deploy@web-02" uptime
```
