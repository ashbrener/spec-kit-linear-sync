#!/usr/bin/env bats
# shellcheck shell=bats
# =============================================================================
# tests/unit/install_config_split.bats — spec 004 (config / identity split)
#
# Unit-level coverage for the install-side of the two-file model:
#   * install::_ensure_operator_local_gitignored adds the *.local.yml glob
#     to .gitignore (creating .gitignore if absent), idempotently, and
#     never silently skips (FR-003 / US2 scenario 2).
#   * install::_write_operator_local_file scaffolds the gitignored
#     identity file from the resolved viewer state, and does NOT clobber
#     an existing operator-edited file (FR-002 / FR-003).
#   * install::write_config writes NO operator block into the committed
#     linear-config.yml (FR-001 / FR-002).
#
# These exercise the install helpers directly (sourcing install.sh
# without invoking install::main), so no live network / GraphQL is
# needed.
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    export PROJECT_ROOT
    TEST_TMP="${BATS_TEST_TMPDIR}/work"
    mkdir -p "${TEST_TMP}"
    cd "${TEST_TMP}" || exit 1
    unset LINEAR_API_KEY
}

_source_install_sh() {
    # shellcheck source=../../src/install.sh disable=SC1091
    source "${PROJECT_ROOT}/src/install.sh"
}

# ---------------------------------------------------------------------------
# .gitignore guarantee (FR-003)
# ---------------------------------------------------------------------------

@test "FR-003: ensure_operator_local_gitignored creates .gitignore when absent" {
    run bash -c "cd '${TEST_TMP}'; source '${PROJECT_ROOT}/src/install.sh'; install::_ensure_operator_local_gitignored"
    [ "${status}" -eq 0 ]
    [ -f "${TEST_TMP}/.gitignore" ]
    grep -qxF '.specify/extensions/linear/*.local.yml' "${TEST_TMP}/.gitignore"
}

@test "FR-003: ensure_operator_local_gitignored appends the entry when absent from an existing .gitignore" {
    printf 'node_modules/\n.env\n' > "${TEST_TMP}/.gitignore"
    run bash -c "cd '${TEST_TMP}'; source '${PROJECT_ROOT}/src/install.sh'; install::_ensure_operator_local_gitignored"
    [ "${status}" -eq 0 ]
    grep -qxF '.specify/extensions/linear/*.local.yml' "${TEST_TMP}/.gitignore"
    # Existing entries preserved.
    grep -qxF '.env' "${TEST_TMP}/.gitignore"
}

@test "FR-003: ensure_operator_local_gitignored is idempotent (no duplicate entry)" {
    bash -c "cd '${TEST_TMP}'; source '${PROJECT_ROOT}/src/install.sh'; install::_ensure_operator_local_gitignored; install::_ensure_operator_local_gitignored"
    local count
    count="$(grep -cxF '.specify/extensions/linear/*.local.yml' "${TEST_TMP}/.gitignore")"
    [ "${count}" -eq 1 ]
}

# ---------------------------------------------------------------------------
# operator-local file scaffold (FR-002 / FR-003)
# ---------------------------------------------------------------------------

@test "FR-002: write_operator_local_file scaffolds a gitignored identity file" {
    run bash -c "
        cd '${TEST_TMP}'
        source '${PROJECT_ROOT}/src/install.sh'
        INSTALL_SESSION_VIEWER_ID='44444444-4444-4444-4444-444444444444'
        INSTALL_SESSION_VIEWER_NAME='Test Operator'
        INSTALL_SESSION_VIEWER_EMAIL='test@example.com'
        install::_write_operator_local_file
    "
    [ "${status}" -eq 0 ]
    local opfile="${TEST_TMP}/.specify/extensions/linear/linear-operator.local.yml"
    [ -f "${opfile}" ]
    grep -q '44444444-4444-4444-4444-444444444444' "${opfile}"
    grep -q 'Test Operator' "${opfile}"
    grep -q 'NEVER COMMIT' "${opfile}"
}

@test "FR-002: write_operator_local_file is a no-op when no identity resolved" {
    run bash -c "
        cd '${TEST_TMP}'
        source '${PROJECT_ROOT}/src/install.sh'
        INSTALL_SESSION_VIEWER_ID=''
        INSTALL_OPERATOR_USER_ID=''
        install::_write_operator_local_file
    "
    [ "${status}" -eq 0 ]
    [ ! -f "${TEST_TMP}/.specify/extensions/linear/linear-operator.local.yml" ]
}

@test "FR-002: write_operator_local_file does NOT clobber an existing operator-edited file" {
    local opfile="${TEST_TMP}/.specify/extensions/linear/linear-operator.local.yml"
    mkdir -p "$(dirname "${opfile}")"
    printf 'schema_version: 1\noperator:\n  user_id: "99999999-9999-9999-9999-999999999999"\n' > "${opfile}"
    run bash -c "
        cd '${TEST_TMP}'
        source '${PROJECT_ROOT}/src/install.sh'
        INSTALL_SESSION_VIEWER_ID='44444444-4444-4444-4444-444444444444'
        install::_write_operator_local_file
    "
    [ "${status}" -eq 0 ]
    # Existing identity preserved.
    grep -q '99999999-9999-9999-9999-999999999999' "${opfile}"
    ! grep -q '44444444-4444-4444-4444-444444444444' "${opfile}"
}

# ---------------------------------------------------------------------------
# committed config carries NO operator block (FR-001 / FR-002)
# ---------------------------------------------------------------------------

@test "FR-001: write_config writes no operator block into the committed config" {
    run bash -c "
        cd '${TEST_TMP}'
        source '${PROJECT_ROOT}/src/install.sh'
        # viewer state present — proves identity is NOT routed into the
        # committed file even when it is available.
        INSTALL_SESSION_VIEWER_ID='44444444-4444-4444-4444-444444444444'
        INSTALL_SESSION_VIEWER_NAME='Test Operator'
        INSTALL_SESSION_VIEWER_EMAIL='test@example.com'
        install::write_config '11111111-1111-1111-1111-111111111111' '22222222-2222-2222-2222-222222222222'
    "
    [ "${status}" -eq 0 ]
    local cfg="${TEST_TMP}/.specify/extensions/linear/linear-config.yml"
    [ -f "${cfg}" ]
    # The committed config must carry the resolved binding UUIDs ...
    grep -q '11111111-1111-1111-1111-111111111111' "${cfg}"
    grep -q '22222222-2222-2222-2222-222222222222' "${cfg}"
    # ... but NO operator block and NO operator identity.
    ! grep -q 'operator:' "${cfg}"
    ! grep -q '44444444-4444-4444-4444-444444444444' "${cfg}"
    ! grep -q 'test@example.com' "${cfg}"
}
