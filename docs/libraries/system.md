# Library: `system` — Cross-Environment OS, Packages, Services, Users & Checks

`lib/system.sh` provides a unified interface across **Linux** (Ubuntu, Debian, RHEL, Rocky, Alpine, Arch, openSUSE), **macOS**, **Windows Git Bash** (`MSYS2`/`MINGW64`), **WSL**, and **Android Termux**.

---

## 1. Environment & OS Detection

### `mbf::system::env_type`
Returns the runtime environment identifier: `linux`, `wsl`, `macos`, `gitbash`, `termux`, or `unknown`.

```bash
mbf::use system

env_type="$(mbf::system::env_type)"
echo "Running in environment: ${env_type}"
```

### `mbf::system::prefix`
Returns `$PREFIX` (`/data/data/com.termux/files/usr`) on Android Termux, or an empty string on standard Unix/Linux systems. Use this to construct portable paths to `/etc` or `/usr/bin`.

```bash
etc_dir="$(mbf::system::prefix)/etc"
echo "Writable config directory: ${etc_dir}"
```

### `mbf::system::as_root <cmd> [args...]`
Executes `<cmd>` directly when `EUID == 0`, on `termux`, or on `gitbash` (where `sudo` is neither needed nor supported), and uses `mbf::exec::sudo` on non-root Linux/macOS.

```bash
mbf::system::as_root cp ./my-app.conf "$(mbf::system::prefix)/etc/my-app.conf"
```

### `mbf::system::distro`, `mbf::system::version`, & `mbf::system::arch`
- `distro`: Returns the OS/distribution ID (`ubuntu`, `debian`, `rocky`, `alpine`, `macos`, `gitbash`, `termux`).
- `version`: Returns the OS version (`22.04`, `12`, `9`, or kernel release).
- `arch`: Returns normalized CPU architecture (`amd64`, `arm64`, `armv7`).

```bash
printf 'Target: %s %s (%s)\n' \
    "$(mbf::system::distro)" \
    "$(mbf::system::version)" \
    "$(mbf::system::arch)"
```

---

## 2. Unified Package Management

### `mbf::system::pkg_manager`
Detects the active system package manager: `pkg` (Termux), `apt-get`, `dnf`, `yum`, `apk`, `pacman`, `zypper`, `brew`, `winget`, or `choco`.

```bash
pm="$(mbf::system::pkg_manager)"
```

### `mbf::system::pkg_update` & `mbf::system::pkg_install <pkg...>`
Updates the package index and installs one or more packages non-interactively across any supported OS.

```bash
mbf::system::pkg_update
mbf::system::pkg_install curl jq git
```

### `mbf::system::pkg_is_installed <pkg>`
Returns `0` if `<pkg>` is installed in the system package database (`dpkg-query`, `rpm -q`, `apk info -e`, or `command -v`).

```bash
if ! mbf::system::pkg_is_installed "nginx"; then
    mbf::system::pkg_install nginx
fi
```

---

## 3. System Service Controller

### `mbf::system::service <start|stop|restart|reload|enable|disable> <service_name>`
Controls system services across `systemctl`, `service`, `rc-service` (Alpine OpenRC), and `sv` (runit/Termux). Respects `MBF_DRYRUN=1`.

```bash
mbf::system::service reload nginx
mbf::system::service restart php8.2-fpm
```

### `mbf::system::service_is_active <service_name>` & `mbf::system::service_ensure <service_name>`
- `service_is_active`: Returns `0` if the service is currently running.
- `service_ensure`: Enables the service at boot and starts it if it is not already running.

```bash
mbf::system::service_ensure redis-server

if mbf::system::service_is_active "redis-server"; then
    mbf::log::ok "Redis is active"
fi
```

---

## 4. User, SSH Key & Sudoers Management

### `mbf::system::user_exists <username>` & `mbf::system::user_ensure <username> [home_dir] [shell]`
Checks whether a system user exists, or creates the user idempotently with `useradd -m`.

```bash
if ! mbf::system::user_exists "deployer"; then
    mbf::system::user_ensure "deployer" "/home/deployer" "/bin/bash"
fi
```

### `mbf::system::ssh_key_add <username> "<pubkey>" [auth_file]` & `mbf::system::ssh_key_remove <username> <pattern> [auth_file]`
Idempotently adds or removes an SSH public key in `<username>`'s `~/.ssh/authorized_keys` with strict `700`/`600` permissions (no `eval`).

```bash
mbf::system::ssh_key_add "deployer" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... ci@deploy"

# Revoke an old key by comment or fingerprint pattern:
mbf::system::ssh_key_remove "deployer" "old-laptop@dev"
```

### `mbf::system::sudo_nopasswd <username> [cmd_list] [sudoers_dir]`
Creates `/etc/sudoers.d/<username>` with mode `0440` and validates syntax via `visudo -cf` before installing.

```bash
# Allow 'deployer' to reload nginx and php-fpm without a password
mbf::system::sudo_nopasswd "deployer" "/usr/bin/systemctl reload nginx, /usr/bin/systemctl reload php8.2-fpm"
```

---

## 5. Pre-Flight & Input Validation

### `mbf::system::check_cmd <cmd> [expected_ver]`, `check_cmds`, & `check_env`
Verifies required binaries and environment variables before a script performs work.

```bash
# Check a single binary (and optional version)
mbf::system::check_cmd "git" || exit 1

# Check multiple binaries at once
mbf::system::check_cmds docker curl tar || exit 1

# Verify required environment variables are set and non-empty
mbf::system::check_env "DB_HOST" "DB_PASSWORD" || exit 1
```

### `mbf::system::is_alnum`, `is_domain`, `is_ip`, & `is_email`
Validates user inputs safely (for example, before passing values to SQL, Nginx configs, or Certbot).

```bash
mbf::system::is_alnum  "magento2_prod"     || mbf::die "Invalid database name"
mbf::system::is_domain "shop.example.com"  || mbf::die "Invalid domain name"
mbf::system::is_ip     "10.240.0.15"       || mbf::die "Invalid IPv4 address"
mbf::system::is_email  "ops@example.com"   || mbf::die "Invalid email address"
```
