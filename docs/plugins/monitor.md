# Plugin: `monitor` — Server Resource, Performance & Security Review

`plugins/monitor.sh` inspects Linux server resources, CPU/RAM bottlenecks, system logs, active firewall rules, cron schedules, and privileged command history, and exports structured JSON snapshots for SaaS dashboards.

---

## Function Reference & Examples

### 1. `mbf::monitor::resources`
Prints hostname, OS/kernel version, uptime, CPU model and core count, RAM/swap capacity (`free -h` / `/proc/meminfo`), and filesystem disk usage (`df -hP`).

```bash
mbf::use monitor

mbf::monitor::resources
```

### 2. `mbf::monitor::performance`
Prints 1m/5m/15m load averages, the top 5 CPU-consuming processes, the top 5 memory-consuming processes, and a summary of TCP socket states (`ss -s` or `netstat`).

```bash
mbf::monitor::performance
```

### 3. `mbf::monitor::logs [custom_log_file] [max_lines]`
Scans `/var/log/syslog`, `/var/log/messages`, `/var/log/auth.log`, `/var/log/secure` (or `[custom_log_file]` / `journalctl`) for:
- Critical/fatal/panic/OOM-killer errors.
- SSH authentication failures and invalid user attempts.

```bash
# Scan default system logs (last 10 matches per category)
mbf::monitor::logs

# Scan a custom application or syslog file (last 20 matches)
mbf::monitor::logs "/var/log/nginx/error.log" 20
```

### 4. `mbf::monitor::firewall`
Displays active firewall status (`ufw`, `firewalld`, or `iptables`) and listening TCP/UDP network ports (`ss -tuln` or `netstat -tuln`).

```bash
mbf::monitor::firewall
```

### 5. `mbf::monitor::cron [custom_cron_dir]`
Inspects the current user's crontab, `/etc/crontab`, and `/etc/cron.{d,hourly,daily,weekly,monthly}` (or a custom directory).

```bash
mbf::monitor::cron
```

### 6. `mbf::monitor::history [history_file] [max_lines]`
Reviews the last `[max_lines]` commands in `~/.bash_history` (or `[history_file]`) and highlights privileged or destructive commands (`sudo`, `su`, `rm -rf`, `chmod`, `chown`, `iptables`, `ufw`, `passwd`, `useradd`, `systemctl`, `crontab`).

```bash
mbf::monitor::history "/root/.bash_history" 25
```

### 7. `mbf::monitor::report [custom_log_file] [custom_history_file]`
Executes all 6 checks (`resources`, `performance`, `logs`, `firewall`, `cron`, `history`) in a single formatted report.

```bash
mbf::monitor::report > "/var/log/server-review-$(date +%F).txt"
```

### 8. `mbf::monitor::collect_review_json [sshd_config_file]`
Returns a single-line JSON object containing `hostname`, `os_kernel`, `cpu_cores`, `load_1m`, `ssh_permit_root_login`, and `ssh_password_auth` for SaaS webhook ingestion.

```bash
metrics_json="$(mbf::monitor::collect_review_json "/etc/ssh/sshd_config")"
echo "$metrics_json"
# Output: {"hostname":"web01","os_kernel":"Linux 6.1.0","cpu_cores":4,"load_1m":"0.42","ssh_permit_root_login":"no","ssh_password_auth":"no"}
```
