# Plugin: `obfuscator` `[•]` — Bash Script Obfuscation Add-on

`plugins/obfuscator.sh` wraps `bash-obfuscate` (`npm install -g bash-obfuscate`) to obfuscate standalone Bash scripts before distribution or native binary compilation with `shc` (`mbf compile --obfuscate`).

---

## Function Reference & Examples

### 1. `mbf::obfuscator::run <input.sh> [output.sh]`
Obfuscates `<input.sh>` into `[output.sh]` (defaults to `o_<basename>`). Respects `MBF_DRYRUN=1`.

```bash
mbf::use obfuscator

# 1. Export a standalone script first
mbf export deploy.sh -o dist/deploy.sh

# 2. Obfuscate the standalone script
mbf::obfuscator::run "dist/deploy.sh" "dist/deploy.obf.sh"
```

### Using with `mbf compile`
You can also combine tree-shaken export, obfuscation, and `shc` binary compilation in a single CLI command:

```bash
mbf compile deploy.sh -o dist/deploy-bin --obfuscate
```
