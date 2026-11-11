#!/usr/bin/env bash
# @mbf-module: {{MODULE_NAME}}
# @mbf-rank: ••
# mbf:requires log exec
# ==============================================================================
# Custom mbf Extension: {{MODULE_NAME}}
#
# STRICT EXTENSION RULES (Required for `mbf export` & `mbf doctor` compatibility):
# 1. Declare dependencies at the top using `# mbf:requires <mod1> <mod2>`.
# 2. Wrap module-level state variables inside `# mbf:state_start` / `# mbf:state_end`.
# 3. Define functions with the `function` keyword and `<ns>::{{MODULE_NAME}}::<fn>()`
#    naming (or `_mbf_{{MODULE_NAME}}_<fn>()` for internal helpers).
# 4. Closing brace `}` of every function MUST be at column 0 on its own line.
# 5. Never call `exit` inside library/plugin functions — return 0/1 status codes.
# 6. Execute state-changing commands via `mbf::exec::run` to respect `--dry-run`.
# 7. Resolve custom templates via `mbf::template::resolve` or `mbf::template::render`.
# ==============================================================================

# mbf:state_start
MBF_{{MODULE_UPPER}}_DEFAULT="${MBF_{{MODULE_UPPER}}_DEFAULT:-default}"
# mbf:state_end

# Internal helper function (prefixed with `_mbf_{{MODULE_NAME}}_`)
function _mbf_{{MODULE_NAME}}_validate() {
    local target="${1:-}"
    [ -n "$target" ] || return 1
}

# Public extension function
# Usage: mbf::{{MODULE_NAME}}::run <target>
function mbf::{{MODULE_NAME}}::run() {
    local target="${1:-}"
    if ! _mbf_{{MODULE_NAME}}_validate "$target"; then
        mbf::log::error "mbf::{{MODULE_NAME}}::run: target argument is required"
        return 1
    fi

    mbf::log::debug_ext "Executing mbf::{{MODULE_NAME}}::run for target='$target'"
    mbf::exec::run echo "Running {{MODULE_NAME}} on $target"
}
