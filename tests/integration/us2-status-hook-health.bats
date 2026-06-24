#!/usr/bin/env bats
# shellcheck shell=bats
# =============================================================================
# tests/integration/us2-status-hook-health.bats — 014 User Story 2 (P2).
#
# `speckit.linear.status` reports hook-registration health as a first-class
# line (present / partial-with-names / none) and ALWAYS exits 0 — the health
# line never changes status's exit disposition (FR-006 + clarification
# 2026-06-24). A non-interactive status reports but never prompts and never
# mutates .specify/extensions.yml (covers analysis finding C1 / FR-009).
#
# Maps to FR-006 and SC-005.
# =============================================================================

load '../helpers/integration-helpers'
load '../helpers/hookcheck_fixtures'

find_status_sh() { printf '%s' "${PROJECT_ROOT}/src/status.sh"; }

run_status_in_sandbox() {
    local status_sh
    status_sh="$(find_status_sh)"
    (
        cd "$SANDBOX_REPO"
        export SPECKIT_LINEAR_CONFIG="$LINEAR_CONFIG_PATH"
        bash "$status_sh" "$@" 2>&1
    )
}

setup() {
    integration::skip_unless_enabled
    integration::setup_sandbox '001-minimal'
    integration::install_gh_shim_no_pr

    integration::stage_response 'query' \
        '{"data":{"issues":{"nodes":[]},"issue":{"blocks":{"nodes":[]}},"comments":{"nodes":[]}}}'
    integration::stage_response 'default' '{"data":{}}'

    EXT_YML="${SANDBOX_REPO}/.specify/extensions.yml"
}

@test "status: all present → 'all present', exit 0" {
    hookcheck_fixtures::all_present "$EXT_YML"
    run run_status_in_sandbox --spec 001 --no-color
    [ "$status" -eq 0 ]
    [[ "$output" == *"Auto-sync hooks: all present"* ]]
}

@test "status: partial → names the missing hooks, exit 0" {
    hookcheck_fixtures::partial "$EXT_YML"
    run run_status_in_sandbox --spec 001 --no-color
    [ "$status" -eq 0 ]
    [[ "$output" == *"partial"* ]]
    [[ "$output" == *"after_tasks"* ]]
}

@test "status: none → 'none registered' + remediation, exit 0" {
    hookcheck_fixtures::none "$EXT_YML"
    run run_status_in_sandbox --spec 001 --no-color
    [ "$status" -eq 0 ]
    [[ "$output" == *"none registered"* ]]
    [[ "$output" == *"/speckit.linear.install"* ]]
}

@test "status: non-interactive never prompts and never mutates extensions.yml (C1/FR-009)" {
    hookcheck_fixtures::none "$EXT_YML"
    local before after
    before="$(shasum "$EXT_YML" | awk '{print $1}')"
    run run_status_in_sandbox --spec 001 --no-color
    [ "$status" -eq 0 ]
    [[ "$output" != *"Re-register"* ]]              # no prompt in a piped run
    after="$(shasum "$EXT_YML" | awk '{print $1}')"
    [ "$before" = "$after" ]                         # file untouched
}
