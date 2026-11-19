#!/usr/bin/env bash
# @mbf-module: ssh
# mbf:requires log exec
# ==============================================================================
# mbf core library: ssh
# Agentless SSH remote execution, ControlMaster multiplexing, file sync &
# on-the-fly tree-shaken script streaming (`mbf::ssh::exec_script`)
#
# Environment Variables:
#   MBF_SSH_PORT            : Custom SSH port (optional)
#   MBF_SSH_KEY             : Path to SSH private key (`-i`, optional)
#   MBF_SSH_TIMEOUT         : Connection timeout in seconds (default: 10)
#   MBF_SSH_OPTS            : Extra space-separated ssh flags (optional)
#   MBF_SSH_MUX_DIR         : ControlMaster socket directory (default: $TMPDIR/mbf-ssh-mux)
#   MBF_SSH_CONTROL_PERSIST : ControlPersist duration in seconds (default: 60)
#   MBF_SSH_PARALLEL        : Set to "1" to run `mbf::ssh::run_many` hosts concurrently
#   MBF_SSH_SELF_REMOVE     : Set to "1" to stage `exec_script` as a 0700 remote temp file
#                             that deletes itself on exit/error (same as `--self-remove`)
# ==============================================================================

# mbf:state_start
MBF_SSH_PORT="${MBF_SSH_PORT:-}"
MBF_SSH_KEY="${MBF_SSH_KEY:-}"
MBF_SSH_TIMEOUT="${MBF_SSH_TIMEOUT:-10}"
MBF_SSH_OPTS="${MBF_SSH_OPTS:-}"
MBF_SSH_MUX_DIR="${MBF_SSH_MUX_DIR:-${TMPDIR:-/tmp}/mbf-ssh-mux}"
MBF_SSH_CONTROL_PERSIST="${MBF_SSH_CONTROL_PERSIST:-60}"
MBF_SSH_PARALLEL="${MBF_SSH_PARALLEL:-0}"
MBF_SSH_SELF_REMOVE="${MBF_SSH_SELF_REMOVE:-0}"
# mbf:state_end

# Compute a short, filesystem-safe ControlPath socket for `<host>` (Unix sockets limit ~104 chars)
function _mbf_ssh_mux_path() {
    local host="$1"
    local port="${MBF_SSH_PORT:-22}"
    local safe="${host//[^a-zA-Z0-9._-]/_}"
    safe="${safe:0:40}"
    printf '%s/mbf_%s_%s.sock\n' "${MBF_SSH_MUX_DIR}" "$safe" "$port"
}

# Safely shell-quote arguments into a single command string for remote execution
function _mbf_ssh_quote_args() {
    local out="" arg q
    for arg in "$@"; do
        printf -v q '%q' "$arg"
        out="${out:+${out} }${q}"
    done
    printf '%s' "$out"
}

# Populate caller-local `_MBF_SSH_ARGS` array with standard SSH options for `<host>`
function _mbf_ssh_build_opts() {
    local host="$1"
    _MBF_SSH_ARGS=(-o BatchMode=yes -o "ConnectTimeout=${MBF_SSH_TIMEOUT:-10}")
    [ -n "${MBF_SSH_PORT:-}" ] && _MBF_SSH_ARGS+=(-p "$MBF_SSH_PORT")
    [ -n "${MBF_SSH_KEY:-}" ] && _MBF_SSH_ARGS+=(-i "$MBF_SSH_KEY")

    local mux_path
    mux_path="$(_mbf_ssh_mux_path "$host")"
    if [ -S "$mux_path" ]; then
        _MBF_SSH_ARGS+=(-o "ControlPath=${mux_path}")
    fi

    if [ -n "${MBF_SSH_OPTS:-}" ]; then
        local -a extra=()
        read -r -a extra <<< "$MBF_SSH_OPTS"
        _MBF_SSH_ARGS+=("${extra[@]}")
    fi
}

# Open a persistent multiplexed SSH connection (`ControlMaster=yes`) for `<host>`
# Automatically registers `mbf::ssh::close` on shell exit.
# Usage: mbf::ssh::open <user@host>
function mbf::ssh::open() {
    local host="${1:-}"
    if [ -z "$host" ]; then
        mbf::log::error "mbf::ssh::open: host is required"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would open multiplexed SSH connection to $host"
        return 0
    fi

    mkdir -p "$MBF_SSH_MUX_DIR" 2>/dev/null || return 1
    chmod 700 "$MBF_SSH_MUX_DIR" 2>/dev/null || true

    local mux_path
    mux_path="$(_mbf_ssh_mux_path "$host")"
    if [ -S "$mux_path" ]; then
        return 0
    fi

    local -a _MBF_SSH_ARGS=()
    _mbf_ssh_build_opts "$host"
    _MBF_SSH_ARGS+=(-M -N -f -o "ControlMaster=yes" -o "ControlPath=${mux_path}" -o "ControlPersist=${MBF_SSH_CONTROL_PERSIST:-60}")

    local status=0
    ssh "${_MBF_SSH_ARGS[@]}" "$host" || status=$?
    if [ "$status" -ne 0 ]; then
        mbf::log::error "mbf::ssh::open: failed to open SSH connection to $host (exit $status)"
        return "$status"
    fi

    local q_host
    printf -v q_host '%q' "$host"
    mbf::exec::on_exit "mbf::ssh::close ${q_host}"
    return 0
}

# Close an active multiplexed SSH connection for `<host>`
# Usage: mbf::ssh::close <user@host>
function mbf::ssh::close() {
    local host="${1:-}"
    [ -n "$host" ] || return 0
    mbf::is_dryrun && return 0

    local mux_path
    mux_path="$(_mbf_ssh_mux_path "$host")"
    if [ -S "$mux_path" ]; then
        ssh -O exit -o "ControlPath=${mux_path}" "$host" >/dev/null 2>&1 || true
        rm -f "$mux_path" 2>/dev/null || true
    fi
    return 0
}

# Execute a command safely on `<host>` via SSH (all arguments are shell-quoted)
# Usage: mbf::ssh::run <user@host> <cmd> [args...]
function mbf::ssh::run() {
    local host="${1:-}"
    shift 1 2>/dev/null || true
    if [ -z "$host" ] || [ $# -eq 0 ]; then
        mbf::log::error "mbf::ssh::run: <host> and <command> are required"
        return 1
    fi

    local remote_cmd
    remote_cmd="$(_mbf_ssh_quote_args "$@")"

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] [ssh:${host}] Would run: ${remote_cmd}"
        return 0
    fi

    local -a _MBF_SSH_ARGS=()
    _mbf_ssh_build_opts "$host"

    local status=0
    ssh "${_MBF_SSH_ARGS[@]}" "$host" "$remote_cmd" || status=$?
    if [ "$status" -ne 0 ]; then
        mbf::log::error "[ssh:${host}] Command failed (exit $status): $*"
    fi
    return "$status"
}

# Execute a multi-line Bash script string on `<host>` over stdin (`bash -s -- [args...]`)
# Usage: mbf::ssh::run_bash <user@host> "<bash_code>" [args...]
function mbf::ssh::run_bash() {
    local host="${1:-}"
    local code="${2:-}"
    shift 2 2>/dev/null || true
    if [ -z "$host" ] || [ -z "$code" ]; then
        mbf::log::error "mbf::ssh::run_bash: <host> and <bash_code> are required"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] [ssh:${host}] Would stream bash script (${#code} bytes)"
        return 0
    fi

    local remote_cmd="bash -s"
    if [ $# -gt 0 ]; then
        remote_cmd="bash -s -- $(_mbf_ssh_quote_args "$@")"
    fi

    local -a _MBF_SSH_ARGS=()
    _mbf_ssh_build_opts "$host"

    local status=0
    printf '%s\n' "$code" | ssh "${_MBF_SSH_ARGS[@]}" "$host" "$remote_cmd" || status=$?
    if [ "$status" -ne 0 ]; then
        mbf::log::error "[ssh:${host}] Remote bash execution failed (exit $status)"
    fi
    return "$status"
}

# Export a local MBF (or plain Bash) script into a tree-shaken standalone script and
# execute it agentlessly on `<host>` over SSH — the remote server needs NO `mbf`.
# With `--self-remove` (or `MBF_SSH_SELF_REMOVE=1`), stages the script to a `0700`
# remote temp file with an injected `EXIT` self-removal trap so the script removes
# itself immediately after execution (even on failure) while keeping `$0` and stdin clean.
# Usage: mbf::ssh::exec_script [--self-remove] <user@host> <local_script.sh> [args...]
function mbf::ssh::exec_script() {
    local self_remove="${MBF_SSH_SELF_REMOVE:-0}"
    if [ "${1:-}" == "--self-remove" ]; then
        self_remove=1
        shift 1
    fi

    local host="${1:-}"
    local script_path="${2:-}"
    shift 2 2>/dev/null || true

    if [ -z "$host" ] || [ -z "$script_path" ] || [ ! -f "$script_path" ]; then
        mbf::log::error "mbf::ssh::exec_script: valid <host> and <local_script.sh> are required"
        return 1
    fi

    if mbf::is_dryrun; then
        if [ "$self_remove" == "1" ]; then
            mbf::log::info "[DRYRUN] [ssh:${host}] Would export, execute, and self-remove ${script_path}${*:+ $*}"
        else
            mbf::log::info "[DRYRUN] [ssh:${host}] Would export and execute ${script_path}${*:+ $*}"
        fi
        return 0
    fi

    local payload_file="$script_path"
    if grep -qE 'mbf[[:space:]]+--init|mbf[[:space:]]+init|framework\.sh|mbf::use' "$script_path" 2>/dev/null; then
        if ! declare -F mbf::exporter::run >/dev/null 2>&1; then
            if [ -f "${MBF_HOME:-}/tools/exporter.sh" ]; then
                # shellcheck disable=SC1091
                source "${MBF_HOME}/tools/exporter.sh"
            fi
        fi
        if declare -F mbf::exporter::run >/dev/null 2>&1; then
            local tmp_export
            mbf::exec::tmpfile tmp_export || return 1
            mbf::exporter::run "$script_path" -o "$tmp_export" || return 1
            payload_file="$tmp_export"
        fi
    fi

    local -a _MBF_SSH_ARGS=()
    _mbf_ssh_build_opts "$host"

    local status=0 remote_cmd q_args=""
    [ $# -gt 0 ] && q_args="$(_mbf_ssh_quote_args "$@")"

    if [ "$self_remove" == "1" ]; then
        local staged_file first_line=""
        mbf::exec::tmpfile staged_file || return 1
        {
            IFS= read -r first_line < "$payload_file" || true
            if [[ "$first_line" == "#!"* ]]; then
                printf '%s\n' "$first_line"
                printf '%s\n' 'trap '\''rm -f -- "${BASH_SOURCE[0]:-$0}"'\'' EXIT'
                tail -n +2 "$payload_file"
            else
                printf '%s\n' '#!/usr/bin/env bash'
                printf '%s\n' 'trap '\''rm -f -- "${BASH_SOURCE[0]:-$0}"'\'' EXIT'
                cat "$payload_file"
            fi
        } > "$staged_file"

        # Single-round-trip remote staging: 0700 temp file + self-removing script + outer trap guard
        remote_cmd="umask 077; _mbf_tmp=\"\$(mktemp \"\${TMPDIR:-/tmp}/mbf.remote.XXXXXX\")\" || exit 1; trap 'rm -f -- \"\$_mbf_tmp\"' EXIT INT TERM; cat > \"\$_mbf_tmp\" && chmod 700 \"\$_mbf_tmp\" && bash \"\$_mbf_tmp\"${q_args:+ ${q_args}} </dev/null"
        ssh "${_MBF_SSH_ARGS[@]}" "$host" "$remote_cmd" < "$staged_file" || status=$?
    else
        remote_cmd="bash -s${q_args:+ -- ${q_args}}"
        ssh "${_MBF_SSH_ARGS[@]}" "$host" "$remote_cmd" < "$payload_file" || status=$?
    fi

    if [ "$status" -ne 0 ]; then
        mbf::log::error "[ssh:${host}] Remote script '${script_path}' failed (exit $status)"
    fi
    return "$status"
}

# Upload a local file or directory to `<host>:<remote_path>` via `scp`
# Usage: mbf::ssh::upload <user@host> <local_path> <remote_path>
function mbf::ssh::upload() {
    local host="${1:-}"
    local local_path="${2:-}"
    local remote_path="${3:-}"

    if [ -z "$host" ] || [ -z "$local_path" ] || [ -z "$remote_path" ]; then
        mbf::log::error "mbf::ssh::upload: <host>, <local_path>, and <remote_path> are required"
        return 1
    fi
    if [ ! -e "$local_path" ]; then
        mbf::log::error "mbf::ssh::upload: local path not found: $local_path"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] [ssh:${host}] Would upload ${local_path} -> ${host}:${remote_path}"
        return 0
    fi

    local -a scp_args=(-o BatchMode=yes -o "ConnectTimeout=${MBF_SSH_TIMEOUT:-10}")
    [ -d "$local_path" ] && scp_args+=(-r)
    [ -n "${MBF_SSH_PORT:-}" ] && scp_args+=(-P "$MBF_SSH_PORT")
    [ -n "${MBF_SSH_KEY:-}" ] && scp_args+=(-i "$MBF_SSH_KEY")

    local mux_path
    mux_path="$(_mbf_ssh_mux_path "$host")"
    [ -S "$mux_path" ] && scp_args+=(-o "ControlPath=${mux_path}")

    local status=0
    scp "${scp_args[@]}" "$local_path" "${host}:${remote_path}" || status=$?
    if [ "$status" -ne 0 ]; then
        mbf::log::error "[ssh:${host}] Upload failed (exit $status): $local_path -> $remote_path"
    fi
    return "$status"
}

# Synchronize a local directory to `<host>:<remote_dir>` via `rsync` over SSH
# Usage: mbf::ssh::sync <user@host> <local_dir> <remote_dir> [extra_rsync_args...]
function mbf::ssh::sync() {
    local host="${1:-}"
    local local_dir="${2:-}"
    local remote_dir="${3:-}"
    shift 3 2>/dev/null || true

    if [ -z "$host" ] || [ -z "$local_dir" ] || [ -z "$remote_dir" ]; then
        mbf::log::error "mbf::ssh::sync: <host>, <local_dir>, and <remote_dir> are required"
        return 1
    fi
    if [ ! -d "$local_dir" ]; then
        mbf::log::error "mbf::ssh::sync: local directory not found: $local_dir"
        return 1
    fi

    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] [ssh:${host}] Would rsync ${local_dir}/ -> ${host}:${remote_dir}/"
        return 0
    fi

    local -a _MBF_SSH_ARGS=()
    _mbf_ssh_build_opts "$host"
    local ssh_transport
    ssh_transport="ssh $(_mbf_ssh_quote_args "${_MBF_SSH_ARGS[@]}")"

    local src="${local_dir%/}/"
    local dst="${remote_dir%/}/"

    local status=0
    rsync -az --delete -e "$ssh_transport" "$@" "$src" "${host}:${dst}" || status=$?
    if [ "$status" -ne 0 ]; then
        mbf::log::error "[ssh:${host}] Sync failed (exit $status): $src -> $dst"
    fi
    return "$status"
}

# Execute a command across multiple hosts (comma- or space-separated).
# Prefixes each output line with `[host]`. Set `MBF_SSH_PARALLEL=1` for concurrent execution.
# Usage: mbf::ssh::run_many "deploy@web1,deploy@web2" uname -a
function mbf::ssh::run_many() {
    local hosts_raw="${1:-}"
    shift 1 2>/dev/null || true
    if [ -z "$hosts_raw" ] || [ $# -eq 0 ]; then
        mbf::log::error "mbf::ssh::run_many: <hosts> and <command> are required"
        return 1
    fi

    local hosts_norm="${hosts_raw//,/ }"
    local -a hosts=()
    read -r -a hosts <<< "$hosts_norm"

    local rc=0 host
    if [ "${MBF_SSH_PARALLEL:-0}" == "1" ]; then
        local -a pids=()
        for host in "${hosts[@]}"; do
            (
                local out h_rc=0
                out="$(mbf::ssh::run "$host" "$@" 2>&1)" || h_rc=$?
                if [ -n "$out" ]; then
                    printf '%s\n' "$out" | sed "s/^/[${host}] /"
                fi
                exit "$h_rc"
            ) &
            pids+=("$!")
        done
        local pid
        for pid in "${pids[@]}"; do
            wait "$pid" || rc=1
        done
    else
        for host in "${hosts[@]}"; do
            local out h_rc=0
            out="$(mbf::ssh::run "$host" "$@" 2>&1)" || h_rc=$?
            if [ -n "$out" ]; then
                printf '%s\n' "$out" | sed "s/^/[${host}] /"
            fi
            [ "$h_rc" -ne 0 ] && rc=1
        done
    fi
    return "$rc"
}
