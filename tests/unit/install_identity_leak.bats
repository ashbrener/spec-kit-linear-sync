#!/usr/bin/env bats
# shellcheck shell=bats
# =============================================================================
# tests/unit/install_identity_leak.bats — spec 004 hardening
#
# Consumer-side operator-identity-leak guard. These tests exercise the
# install-time assertion (install::assert_no_identity_leak) against a
# real, throwaway CONSUMER git repo (NOT the bridge repo) so we cover
# the scenario the bridge-repo no-real-identifiers.bats cannot: an
# install that committed identity into a consumer's tracked tree.
#
# They also lock the fresh-install invariant (FR-002 / FR-003): a fresh
# install never produces a TRACKED file carrying identity — identity
# lives only in the gitignored linear-operator.local.yml, and the
# committed linear-config.yml is identity-free.
#
# All identifiers below are synthetic placeholders (4444…, example.com)
# so this file itself never trips the bridge-repo privacy guard.
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    export PROJECT_ROOT
    TEST_TMP="${BATS_TEST_TMPDIR}/consumer"
    mkdir -p "${TEST_TMP}"
    cd "${TEST_TMP}" || exit 1
    git init -q .
    git config user.email "ci@example.test"
    git config user.name "CI"
    unset LINEAR_API_KEY
    unset SPECKIT_LINEAR_STRICT_IDENTITY
}

CONFIG_DIR=".specify/extensions/linear"

# Run the guard with summary state initialised (it records findings via
# summary::add, which requires summary::start to have run).
_run_guard() {
    run bash -c "
        cd '${TEST_TMP}'
        source '${PROJECT_ROOT}/src/install.sh'
        summary::start 'test'
        install::assert_no_identity_leak
    "
}

# ---------------------------------------------------------------------------
# Clean tree — no leak
# ---------------------------------------------------------------------------

@test "guard: identity-free tracked tree passes cleanly" {
    mkdir -p "${CONFIG_DIR}"
    printf 'linear:\n  team:\n    id: "11111111-1111-1111-1111-111111111111"\n  project:\n    id: "22222222-2222-2222-2222-222222222222"\n' \
        > "${CONFIG_DIR}/linear-config.yml"
    git add -A
    _run_guard
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# operator.* identity keys in a TRACKED committed config — leak
# ---------------------------------------------------------------------------

@test "guard: warns (default) when a tracked config carries an operator.* block" {
    mkdir -p "${CONFIG_DIR}"
    printf 'linear:\n  team:\n    id: "11111111-1111-1111-1111-111111111111"\n  operator:\n    user_id: "44444444-4444-4444-4444-444444444444"\n' \
        > "${CONFIG_DIR}/linear-config.yml"
    git add -A
    _run_guard
    # Default = Principle VIII surface: exit 0 but a loud WARN naming the file.
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"WARN"* ]]
    [[ "${output}" == *"linear-config.yml"* ]]
}

@test "guard: STRICT mode fails (exit 2) on a tracked operator.* block" {
    mkdir -p "${CONFIG_DIR}"
    printf 'linear:\n  operator:\n    user_id: "44444444-4444-4444-4444-444444444444"\n' \
        > "${CONFIG_DIR}/linear-config.yml"
    git add -A
    run bash -c "
        cd '${TEST_TMP}'
        export SPECKIT_LINEAR_STRICT_IDENTITY=1
        source '${PROJECT_ROOT}/src/install.sh'
        summary::start 'test'
        install::assert_no_identity_leak
    "
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"linear-config.yml"* ]]
}

# ---------------------------------------------------------------------------
# Email-shaped string in any TRACKED file — leak
# ---------------------------------------------------------------------------

@test "guard: warns when an email-shaped string is in a tracked file" {
    mkdir -p "${CONFIG_DIR}"
    printf 'linear:\n  notes: "owner operator@example.com"\n' \
        > "${CONFIG_DIR}/linear-config.yml"
    git add -A
    _run_guard
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"WARN"* ]]
    [[ "${output}" == *"email-shaped"* ]]
}

# ---------------------------------------------------------------------------
# Force-added operator-local file — leak (it must be gitignored)
# ---------------------------------------------------------------------------

@test "guard: flags a TRACKED (force-added) operator-local file" {
    mkdir -p "${CONFIG_DIR}"
    printf 'schema_version: 1\noperator:\n  user_id: "44444444-4444-4444-4444-444444444444"\n' \
        > "${CONFIG_DIR}/linear-operator.local.yml"
    git add -f "${CONFIG_DIR}/linear-operator.local.yml"
    _run_guard
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"linear-operator.local.yml"* ]]
    [[ "${output}" == *"TRACKED"* ]]
}

# ---------------------------------------------------------------------------
# Fresh-install invariant: identity only ever lands in the gitignored
# local file; the committed config is identity-free and the local file
# is never tracked. (FR-002 / FR-003)
# ---------------------------------------------------------------------------

@test "fresh install: identity goes only to the gitignored local file, never tracked" {
    run bash -c "
        cd '${TEST_TMP}'
        source '${PROJECT_ROOT}/src/install.sh'
        INSTALL_SESSION_VIEWER_ID='44444444-4444-4444-4444-444444444444'
        INSTALL_SESSION_VIEWER_NAME='Test Operator'
        INSTALL_SESSION_VIEWER_EMAIL='test@example.com'
        # Replicate the install::main ordering: gitignore guard, write
        # committed config, scaffold local identity file.
        install::_ensure_operator_local_gitignored
        install::write_config '11111111-1111-1111-1111-111111111111' '22222222-2222-2222-2222-222222222222'
        install::_write_operator_local_file
    "
    [ "${status}" -eq 0 ]

    local cfg="${TEST_TMP}/${CONFIG_DIR}/linear-config.yml"
    local opfile="${TEST_TMP}/${CONFIG_DIR}/linear-operator.local.yml"

    # Local file holds the identity ...
    [ -f "${opfile}" ]
    grep -q '44444444-4444-4444-4444-444444444444' "${opfile}"

    # ... the committed config does NOT.
    [ -f "${cfg}" ]
    ! grep -q '44444444-4444-4444-4444-444444444444' "${cfg}"
    ! grep -q 'test@example.com' "${cfg}"

    # The local file is gitignored (git would refuse to track it).
    git -C "${TEST_TMP}" check-ignore -q "${CONFIG_DIR}/linear-operator.local.yml"

    # After staging everything, the local file is NOT in the index and
    # the tracked tree carries no identity — the guard passes.
    git -C "${TEST_TMP}" add -A
    run git -C "${TEST_TMP}" ls-files "${CONFIG_DIR}/linear-operator.local.yml"
    [ -z "${output}" ]

    run bash -c "
        cd '${TEST_TMP}'
        source '${PROJECT_ROOT}/src/install.sh'
        summary::start 'test'
        install::assert_no_identity_leak
    "
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 010 — authors-override file (gitignored identity-bearing map)
# ---------------------------------------------------------------------------

@test "guard: a TRACKED authors-override file is flagged (warn) and fails under strict" {
    mkdir -p "${CONFIG_DIR}"
    printf 'linear:\n  team:\n    id: "11111111-1111-1111-1111-111111111111"\n' \
        > "${CONFIG_DIR}/linear-config.yml"
    # Force-track the gitignored authors file (the leak scenario).
    printf 'schema_version: 1\nauthors:\n  dev@example.com:\n    handle: dev\n' \
        > "${CONFIG_DIR}/linear-authors.local.yml"
    git add -A -f
    # Default (surface) mode: warns, exit 0.
    _run_guard
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"linear-authors.local.yml"* ]]
    # Strict mode: hard-fail.
    run bash -c "
        cd '${TEST_TMP}'
        export SPECKIT_LINEAR_STRICT_IDENTITY=1
        source '${PROJECT_ROOT}/src/install.sh'
        summary::start 'test'
        install::assert_no_identity_leak
    "
    [ "${status}" -ne 0 ]
}

@test "guard: the authors .sample with placeholders passes cleanly (SC-006)" {
    mkdir -p "${CONFIG_DIR}"
    printf 'linear:\n  team:\n    id: "11111111-1111-1111-1111-111111111111"\n' \
        > "${CONFIG_DIR}/linear-config.yml"
    # The committed .sample carries example.com placeholders by design.
    printf 'schema_version: 1\nauthors:\n  alice@example.com:\n    handle: alice\n    linear_user_id: "00000000-0000-0000-0000-000000000000"\n' \
        > "${CONFIG_DIR}/linear-authors.local.yml.sample"
    git add -A
    _run_guard
    [ "${status}" -eq 0 ]
}
