# Plugin: `security` `[•••]` — SSH Hardening, System Audit & Firewall Management

`plugins/security.sh` audits and hardens OpenSSH (including `/etc/ssh/sshd_config.d/*.conf` drop-in files used on Ubuntu 22.04+), checks UID 0 accounts and `fail2ban`, and provides a unified firewall interface across `ufw`, `firewalld`, and `iptables`.

---

## Function Reference & Examples

### 1. `mbf::security::audit_ssh [sshd_config_file]`
Audits effective SSH daemon settings (`Port`, `PermitRootLogin`, `PasswordAuthentication`, `PermitEmptyPasswords`) using OpenSSH's first-match-wins rules across `<sshd_config_file>.d/*.conf` and `<sshd_config_file>`. Prints `[RISK]` or `[WARN]` findings.

```bash
mbf::use security

mbf::security::audit_ssh "/etc/ssh/sshd_config"
```

### 2. `mbf::security::harden_ssh [sshd_config_file] [disable_password_auth:0|1]`
Safely hardens SSH configuration:
1. Creates a `.mbf.bak` backup of `sshd_config`.
2. Sets `PermitRootLogin no` and `PermitEmptyPasswords no`.
3. When `disable_password_auth` is `1` (default), sets `PasswordAuthentication no` in both `sshd_config` and any `<sshd_config>.d/*.conf` drop-in files.
4. Validates syntax with `sshd -t -f` before reloading SSH (automatically rolls back from `.mbf.bak` if validation fails).

```bash
# Harden SSH and disable password authentication (key-only login)
mbf::security::harden_ssh "/etc/ssh/sshd_config" 1
```

### 3. `mbf::security::audit_system [passwd_file]`
Lists all accounts with UID `0` (root privileges) in `/etc/passwd` and checks whether `fail2ban` is installed.

```bash
mbf::security::audit_system
```

### 4. `mbf::security::install_fail2ban`
Installs `fail2ban` via the OS package manager and ensures the `fail2ban` service is enabled and running.

```bash
mbf::security::install_fail2ban
```

### 5. `mbf::security::fw_backend`
Detects the active firewall tool (`ufw`, `firewalld`, or `iptables`, or `$MBF_FIREWALL_BACKEND` override).

```bash
fw="$(mbf::security::fw_backend)"
echo "Detected firewall backend: ${fw}"
```

### 6. `mbf::security::fw_allow <port> [tcp|udp]` & `mbf::security::fw_deny <port> [tcp|udp]`
Idempotently allows or denies incoming traffic on `<port>/<proto>` across `ufw`, `firewalld`, or `iptables` (uses `iptables -C` before `-A` so duplicate rules are never added).

```bash
# Open HTTPS and custom Varnish admin port
mbf::security::fw_allow 443 tcp
mbf::security::fw_allow 6081 tcp

# Block external access to MySQL port
mbf::security::fw_deny 3306 tcp
```

### 7. `mbf::security::fw_enable_baseline [ssh_port]`
Safely enables baseline firewall rules without locking out the operator:
1. Explicitly allows `[ssh_port]` (default: `22`), HTTP (`80/tcp`), and HTTPS (`443/tcp`).
2. On `ufw`, sets `default deny incoming`, `default allow outgoing`, and enables the firewall (`ufw --force enable`).

```bash
# Allow SSH (port 22), 80, and 443, then enable firewall
mbf::security::fw_enable_baseline 22
```
