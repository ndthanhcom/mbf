#!/usr/bin/env bash
# mbf:requires log
# ==============================================================================
# mbf plugin: monitor
# Linux Server Monitoring & Security/Operations Review Tools
# ==============================================================================

function _mbf_monitor_header() {
    printf '\n=== %s ===\n' "$1"
}

# 1. Server Resources: Specs & Available Capacity
function mbf::monitor::resources() {
    _mbf_monitor_header "SERVER RESOURCES (SPECS & AVAILABLE)"

    printf 'Hostname : %s\n' "$(hostname 2>/dev/null || echo 'unknown')"
    printf 'OS/Kernel: %s\n' "$(uname -sr 2>/dev/null || echo 'unknown')"
    command -v uptime >/dev/null 2>&1 && printf 'Uptime   : %s\n' "$(uptime)"

    local cpu_cores="unknown" cpu_model="generic"
    if [ -r /proc/cpuinfo ]; then
        cpu_cores="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)"
        cpu_model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[[:space:]]*//')"
    elif command -v nproc >/dev/null 2>&1; then
        cpu_cores="$(nproc)"
    fi
    printf 'CPU      : %s (%s cores)\n' "${cpu_model:-generic}" "$cpu_cores"

    printf '\n[Memory Usage]\n'
    if command -v free >/dev/null 2>&1; then
        free -h 2>/dev/null || free -m
    elif [ -r /proc/meminfo ]; then
        grep -E '^(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo
    else
        echo "Memory info utility (free / /proc/meminfo) not available"
    fi

    printf '\n[Disk Usage]\n'
    if command -v df >/dev/null 2>&1; then
        df -hP 2>/dev/null | grep -vE '^tmpfs|^devtmpfs|^udev' || df -h
    fi
}

# 2. Server Performance Check
function mbf::monitor::performance() {
    _mbf_monitor_header "PERFORMANCE CHECK"

    if [ -r /proc/loadavg ]; then
        printf 'Load Average (1m, 5m, 15m): %s\n' "$(awk '{print $1, $2, $3}' /proc/loadavg)"
    elif command -v uptime >/dev/null 2>&1; then
        printf 'Load Average: %s\n' "$(uptime | awk -F'load average:' '{print $2}')"
    fi

    printf '\n[Top 5 CPU Processes]\n'
    if ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu >/dev/null 2>&1; then
        ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -n 6
    else
        ps aux 2>/dev/null | head -n 6
    fi

    printf '\n[Top 5 Memory Processes]\n'
    if ps -eo pid,user,%mem,%cpu,comm --sort=-%mem >/dev/null 2>&1; then
        ps -eo pid,user,%mem,%cpu,comm --sort=-%mem | head -n 6
    fi

    printf '\n[Network Connections Summary]\n'
    if command -v ss >/dev/null 2>&1; then
        ss -s 2>/dev/null | head -n 10
    elif command -v netstat >/dev/null 2>&1; then
        netstat -an 2>/dev/null | awk '/^tcp/ {++state[$NF]} END {for(k in state) print k, state[k]}'
    else
        echo "Neither ss nor netstat found"
    fi
}

# 3. Logs Analyzer
# Usage: mbf::monitor::logs [custom_log_file] [max_lines]
function mbf::monitor::logs() {
    local custom_log="${1:-${MBF_MONITOR_LOG_FILE:-}}"
    local max_lines="${2:-10}"

    _mbf_monitor_header "LOGS ANALYZER"

    local -a log_candidates=()
    if [ -n "$custom_log" ]; then
        log_candidates=("$custom_log")
    else
        log_candidates=("/var/log/syslog" "/var/log/messages" "/var/log/auth.log" "/var/log/secure")
    fi

    local found_log=0 lf
    for lf in "${log_candidates[@]}"; do
        if [ -r "$lf" ]; then
            found_log=1
            printf '\nAnalyzing log file: %s\n' "$lf"
            local err_count auth_fail_count
            err_count="$(grep -iEc 'error|critical|fatal|panic|oom-killer|out of memory' "$lf" 2>/dev/null || echo 0)"
            auth_fail_count="$(grep -iEc 'failed password|authentication failure|invalid user' "$lf" 2>/dev/null || echo 0)"
            printf '  Total error/critical matches: %s\n' "$err_count"
            printf '  Total auth failure matches  : %s\n' "$auth_fail_count"

            if [ "$err_count" -gt 0 ]; then
                printf '  Recent error entries (last %d):\n' "$max_lines"
                grep -iE 'error|critical|fatal|panic|oom-killer|out of memory' "$lf" 2>/dev/null | tail -n "$max_lines" | sed 's/^/    /'
            fi
            if [ "$auth_fail_count" -gt 0 ]; then
                printf '  Recent auth failure entries (last %d):\n' "$max_lines"
                grep -iE 'failed password|authentication failure|invalid user' "$lf" 2>/dev/null | tail -n "$max_lines" | sed 's/^/    /'
            fi
        fi
    done

    if [ "$found_log" -eq 0 ]; then
        if command -v journalctl >/dev/null 2>&1; then
            printf 'Checking systemd journal (last %d errors):\n' "$max_lines"
            journalctl -p err -n "$max_lines" --no-pager 2>/dev/null || echo "Unable to read journalctl"
        else
            echo "No readable system log files found."
        fi
    fi
}

# 4. Firewall & Listening Ports Check
function mbf::monitor::firewall() {
    _mbf_monitor_header "FIREWALL & PORTS CHECK"

    local fw_detected=0
    if command -v ufw >/dev/null 2>&1; then
        fw_detected=1
        printf '[UFW Status]\n'
        ufw status verbose 2>/dev/null || echo "UFW installed (requires root to inspect active rules)"
    fi
    if command -v firewall-cmd >/dev/null 2>&1; then
        fw_detected=1
        printf '[Firewalld Status]\n'
        firewall-cmd --state 2>/dev/null || echo "Firewalld installed (inactive or requires root)"
    fi
    if command -v iptables >/dev/null 2>&1; then
        fw_detected=1
        printf '[Iptables Rules]\n'
        iptables -L -n 2>/dev/null | head -n 20 || echo "Iptables installed (requires root to list rules)"
    fi
    if [ "$fw_detected" -eq 0 ]; then
        echo "No standard Linux firewall utility (ufw, firewalld, iptables) detected in PATH."
    fi

    printf '\n[Listening Network Ports]\n'
    if command -v ss >/dev/null 2>&1; then
        ss -tuln 2>/dev/null | head -n 20
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln 2>/dev/null | head -n 20
    fi
}

# 5. Cron Jobs Check
# Usage: mbf::monitor::cron [custom_cron_dir]
function mbf::monitor::cron() {
    local custom_dir="${1:-}"
    _mbf_monitor_header "CRON JOBS CHECK"

    if [ -n "$custom_dir" ] && [ -d "$custom_dir" ]; then
        printf '[Custom Cron Directory: %s]\n' "$custom_dir"
        grep -rnv '^[[:space:]]*\(#\|$\)' "$custom_dir" 2>/dev/null || echo "No active cron entries"
        return 0
    fi

    printf '[Current User Crontab (%s)]\n' "${USER:-$(id -un 2>/dev/null || echo current)}"
    if command -v crontab >/dev/null 2>&1; then
        crontab -l 2>/dev/null | grep -vE '^[[:space:]]*(#|$)' || echo "No active user crontab entries"
    else
        echo "crontab command not available"
    fi

    [ -r /etc/crontab ] && { printf '\n[/etc/crontab]\n'; grep -vE '^[[:space:]]*(#|$)' /etc/crontab; }

    local cron_dir
    for cron_dir in /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
        if [ -d "$cron_dir" ]; then
            printf '\n[%s]\n' "$cron_dir"
            ls -1 "$cron_dir" 2>/dev/null | sed 's/^/  /'
        fi
    done
}

# 6. Command History Review
# Usage: mbf::monitor::history [history_file] [max_lines]
function mbf::monitor::history() {
    local hist_file="${1:-${MBF_HISTORY_FILE:-${HISTFILE:-$HOME/.bash_history}}}"
    local max_lines="${2:-20}"

    _mbf_monitor_header "COMMAND HISTORY REVIEW"

    if [ ! -r "$hist_file" ]; then
        printf 'History file not found or not readable: %s\n' "$hist_file"
        return 0
    fi

    printf 'Source: %s\n' "$hist_file"
    printf '\n[Last %d Commands]\n' "$max_lines"
    tail -n "$max_lines" "$hist_file" | sed 's/^/  /'

    printf '\n[Privileged / Sensitive Commands in History]\n'
    grep -E '(^|[[:space:]])(sudo|su|rm[[:space:]]+-rf|chmod|chown|iptables|ufw|passwd|useradd|usermod|systemctl|crontab)\b' "$hist_file" 2>/dev/null | tail -n "$max_lines" | sed 's/^/  /' || echo "  None found"
}

# 7. Complete Server Review Report
# Usage: mbf::monitor::report [custom_log_file] [custom_history_file]
function mbf::monitor::report() {
    local custom_log="${1:-}"
    local custom_hist="${2:-}"

    printf '==============================================================================\n'
    printf 'MBF LINUX SERVER MONITORING & REVIEW REPORT\n'
    printf 'Generated at: %s\n' "$(date +'%Y-%m-%d %H:%M:%S %z')"
    printf '==============================================================================\n'

    mbf::monitor::resources
    mbf::monitor::performance
    mbf::monitor::logs "$custom_log"
    mbf::monitor::firewall
    mbf::monitor::cron
    mbf::monitor::history "$custom_hist"
}
