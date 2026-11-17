# Plugin: `runtime` `[•]` — Polyglot Node.js, Python & Binary Integration

`plugins/runtime.sh` bridges Bash scripts with external system packages, Node.js scripts (`.js`), and Python scripts (`.py`). When you export a script that calls `mbf::runtime::run_node` or `mbf::runtime::run_python` via `mbf export`, the exporter automatically bundles the referenced `.js`/`.py` files, `package.json`, `requirements.txt`, and a generated `INSTALL.md` into a self-contained directory.

---

## Environment Variables

- `MBF_AUTO_INSTALL=1` — When set, `mbf::runtime::ensure_pkg` automatically installs missing packages via `mbf::system::pkg_install`.
- `MBF_NODE_BIN` — Custom Node.js binary name or path (default: `node`).
- `MBF_PYTHON_BIN` — Custom Python binary name or path (default: `python3` or `python`).

---

## Function Reference & Examples

### 1. `mbf::runtime::install_hint <pkg_name> [download_url]`
Prints OS-specific package installation instructions (`apt-get`, `dnf`, `apk`, `pacman`, `zypper`, `brew`, `pkg`, `winget`, `choco`) and an optional direct download URL.

```bash
mbf::use runtime

mbf::runtime::install_hint "ripgrep" "https://github.com/BurntSushi/ripgrep/releases"
```

### 2. `mbf::runtime::ensure_pkg <pkg_name> [cmd_name] [download_url]`
Checks whether `[cmd_name]` (defaults to `<pkg_name>`) is in `PATH`. If missing:
- Prints OS-specific installation instructions via `mbf::runtime::install_hint`.
- If `MBF_AUTO_INSTALL=1` is set, installs `<pkg_name>` automatically via `mbf::system::pkg_install`.

```bash
# Require `jq` (or auto-install if MBF_AUTO_INSTALL=1)
mbf::runtime::ensure_pkg "jq" "jq" "https://jqlang.github.io/jq/" || exit 1
```

### 3. `mbf::runtime::download <url> <dest_path> [expected_sha256]`
Downloads a binary or script atomically via `mbf::net::download`, verifies `[expected_sha256]` if provided, and marks `<dest_path>` executable (`chmod +x`).

```bash
mbf::runtime::download "https://deployer.org/deployer.phar" "/usr/local/bin/dep"
```

### 4. `mbf::runtime::check_node [min_major]`, `npm_install [dir]`, & `run_node <script.js> [args...]`
Verifies Node.js presence and minimum major version, installs `package.json` dependencies, and executes a `.js` file (preserving `stdin`, `stdout`, and CLI arguments).

```bash
# Verify Node.js >= v18 is installed
mbf::runtime::check_node 18 || exit 1

# Run npm install in the script's directory
mbf::runtime::npm_install "$MBF_SCRIPT_DIR"

# Execute a helper Node.js script with arguments
mbf::runtime::run_node "scripts/parse-sitemap.js" "--url=https://shop.example.com/sitemap.xml"
```

### 5. `mbf::runtime::check_python [min_major]`, `pip_install [req_file] [venv_dir]`, & `run_python <script.py> [args...]`
Verifies Python 3 presence, installs `requirements.txt` (optionally creating a virtualenv in `[venv_dir]`), and executes a `.py` script.

```bash
# Verify Python >= 3 is installed
mbf::runtime::check_python 3 || exit 1

# Install requirements into a local .venv directory
mbf::runtime::pip_install "requirements.txt" "${MBF_SCRIPT_DIR}/.venv"

# Pipe log lines into a Python anomaly detector script
tail -n 200 /var/log/nginx/access.log | mbf::runtime::run_python "scripts/detect_anomalies.py" "--threshold=5"
```
