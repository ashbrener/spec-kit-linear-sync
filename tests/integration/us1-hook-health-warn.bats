#!/usr/bin/env bats
# shellcheck shell=bats
# =============================================================================
# tests/integration/us1-hook-health-warn.bats — 014 User Story 1 (P1).
#
# A reconcile in a repo whose `after_*` auto-sync hooks were stripped (the
# `--force` update failure mode) emits ONE loud named warning + remediation
# and STILL completes (non-blocking). A fully-registered set — or a
# deliberately disabled hook — emits no hook-health warning.
#
# Maps to FR-002/FR-003/FR-004/FR-005/FR-010 and SC-001/SC-002/SC-003/SC-006.
# Reconcile here is non-interactive (no tty) so the self-heal offer never
# fires — this story exercises the warn path; the consent path is unit-tested
# in tests/unit/hookcheck_selfheal.bats.
# =============================================================================

load '../helpers/integration-helpers'
load '../helpers/hookcheck_fixtures'

setup() {
    integration::skip_unless_enabled
    integration::setup_sandbox '001-minimal'
    integration::install_gh_shim_no_pr

    integration::stage_response 'query' \
        '{"data":{"issues":{"nodes":[]},"issue":{"blocks":{"nodes":[]}},"comments":{"nodes":[]}}}'
    integration::stage_response 'mutation' \
        '{"data":{"issueCreate":{"success":true,"issue":{"id":"11111111-1111-4111-1111-111111111111","identifier":"ACM-1","title":"created"}}}}'
    integration::stage_response 'default' '{"data":{}}'

    EXT_YML="${SANDBOX_REPO}/.specify/extensions.yml"
}

@test "stripped hooks → reconcile warns (named + remediation) and is NOT blocked" {
    hookcheck_fixtures::none "$EXT_YML"

    run integration::run_reconcile --spec 001
    [ "$status" -eq 0 ]                                   # SC-003 non-blocking
    [[ "$output" == *"auto-sync hook(s) not registered"* ]]  # SC-001
    [[ "$output" == *"/speckit.linear.install"* ]]
}

@test "partial → warns naming exactly the absent hooks" {
    hookcheck_fixtures::partial "$EXT_YML"   # specify/clarify/plan present; rest absent

    run integration::run_reconcile --spec 001
    [ "$status" -eq 0 ]
    [[ "$output" == *"after_tasks"* ]]
    [[ "$output" == *"after_implement"* ]]
    [[ "$output" == *"after_analyze"* ]]
}

@test "all six registered → no hook-health warning (SC-002)" {
    hookcheck_fixtures::all_present "$EXT_YML"

    run integration::run_reconcile --spec 001
    [[ "$output" != *"auto-sync hook(s) not registered"* ]]
}

@test "a deliberately disabled hook is not 'missing' → no warning (FR-004)" {
    hookcheck_fixtures::one_disabled "$EXT_YML"

    run integration::run_reconcile --spec 001
    [[ "$output" != *"auto-sync hook(s) not registered"* ]]
}

@test "warning fires at most once across an --all sweep (SC-006)" {
    hookcheck_fixtures::none "$EXT_YML"

    run integration::run_reconcile --all
    local count
    count="$(printf '%s\n' "$output" | grep -c 'auto-sync hook(s) not registered' || true)"
    [ "$count" -eq 1 ]
}
