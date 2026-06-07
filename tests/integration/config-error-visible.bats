#!/usr/bin/env bats
# shellcheck shell=bats
# =============================================================================
# tests/integration/config-error-visible.bats — regression for #35
#
# Bug: `pull.sh` and `status.sh` wrapped their `config::load` /
# `config::validate` calls in `2>/dev/null`. The config loader reports a
# malformed `linear-config.yml` via `config::_die`, which prints a
# diagnostic to STDERR and then `exit 2`. The stderr redirect ate the
# only message AND, because `_die` exits rather than returns, the
# friendly fallback hint under the `if` never ran — so the commands
# exited RC=2 with ZERO output. (seed.sh calls config::load WITHOUT the
# redirect, which is why seed surfaced the message.)
#
# Fix: drop the `2>/dev/null` so the `config::_die` diagnostic reaches
# the operator, matching seed.sh.
#
# These tests corrupt the config by wrapping a value onto its own line
# (producing a line with no `key: value` separator) and assert that both
# commands exit 2 AND emit a non-empty "malformed line" diagnostic on
# STDERR. On the old (buggy) code stderr is empty → these fail.
# =============================================================================

load '../helpers/integration-helpers'

find_pull_sh() {
    printf '%s' "${PROJECT_ROOT}/src/pull.sh"
}

find_status_sh() {
    printf '%s' "${PROJECT_ROOT}/src/status.sh"
}

# Run a command in the sandbox capturing ONLY its stderr (the channel the
# bug swallowed). Stdout is discarded so the assertions can't be fooled
# by a diagnostic that leaked to stdout instead.
run_capturing_stderr() {
    local cmd="$1"; shift
    (
        cd "$SANDBOX_REPO"
        export SPECKIT_LINEAR_CONFIG="$LINEAR_CONFIG_PATH"
        bash "$cmd" "$@" 2>&1 1>/dev/null
    )
}

# Wrap the `name:` value under linear.workspace onto its own line so that
# the orphaned value line has no `key: value` separator — exactly the
# shape config.sh flags as a "malformed line".
corrupt_config() {
    cat > "$LINEAR_CONFIG_PATH" <<'YAML'
schema_version: 1
config_version: 1

linear:
  workspace:
    name:
      "ACME"
    url_key: "acme"
YAML
}

# -----------------------------------------------------------------------------
@test "pull surfaces a malformed-config diagnostic on stderr (not silent RC=2)" {
    integration::skip_unless_enabled
    integration::setup_sandbox '001-minimal'
    corrupt_config

    run run_capturing_stderr "$(find_pull_sh)"

    [ "$status" -eq 2 ]
    [ -n "$output" ]
    [[ "$output" == *"malformed line"* ]]
}

# -----------------------------------------------------------------------------
@test "status surfaces a malformed-config diagnostic on stderr (not silent RC=2)" {
    integration::skip_unless_enabled
    integration::setup_sandbox '001-minimal'
    corrupt_config

    run run_capturing_stderr "$(find_status_sh)"

    [ "$status" -eq 2 ]
    [ -n "$output" ]
    [[ "$output" == *"malformed line"* ]]
}
