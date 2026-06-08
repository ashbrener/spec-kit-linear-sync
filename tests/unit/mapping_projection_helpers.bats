#!/usr/bin/env bats
# tests/unit/mapping_projection_helpers.bats — spec 007 projection leaf helpers.
#
# Covers the marker-based identity helpers and the idempotent Initiative/Project
# ensure_* leaf helpers (sub-increment 1 of the projection build). The GraphQL
# transport is stubbed (graphql::query/mutate overridden after sourcing) so the
# tests are hermetic and offline — they assert the helper's idempotency contract
# (create when absent, skip when unchanged, update when changed) and its return
# value, not the wire protocol (which graphql.bats covers).

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
export RECONCILE_SH="${SRC_ROOT}/src/reconcile.sh"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-proj-XXXXXX")"
    export TEST_TMP
    export CALLS="${TEST_TMP}/calls"
    : > "${CALLS}"
}

teardown() {
    if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
        rm -rf "${TEST_TMP}"
    fi
}

# ---------------------------------------------------------------------------
# Pure marker helpers
# ---------------------------------------------------------------------------

@test "mapping_id_marker composes the stable comment marker" {
    run bash -c "source '${RECONCILE_SH}' 2>/dev/null; reconcile::mapping_id_marker 'speckit-repo:my-repo'"
    [ "${status}" -eq 0 ]
    [ "${output}" = "<!-- speckit-id: speckit-repo:my-repo -->" ]
}

@test "mapping_id_extract round-trips an embedded marker" {
    run bash -c "source '${RECONCILE_SH}' 2>/dev/null; m=\$(reconcile::mapping_id_marker 'speckit-spec:007'); reconcile::mapping_id_extract \"prefix \$m suffix\""
    [ "${status}" -eq 0 ]
    [ "${output}" = "speckit-spec:007" ]
}

@test "mapping_id_extract returns empty when no marker is present" {
    run bash -c "source '${RECONCILE_SH}' 2>/dev/null; reconcile::mapping_id_extract 'just a plain description'"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "_compose_marked_description appends the marker and is idempotent" {
    run bash -c "source '${RECONCILE_SH}' 2>/dev/null
        d1=\$(reconcile::_compose_marked_description 'Body text' 'speckit-spec:007')
        d2=\$(reconcile::_compose_marked_description \"\$d1\" 'speckit-spec:007')
        [ \"\$d1\" = \"\$d2\" ] || { echo NOT_IDEMPOTENT; exit 1; }
        case \"\$d1\" in *'<!-- speckit-id: speckit-spec:007 -->'*) echo HAS_MARKER;; *) echo NO_MARKER;; esac"
    [ "${status}" -eq 0 ]
    [ "${output}" = "HAS_MARKER" ]
}

# ---------------------------------------------------------------------------
# ensure_initiative
# ---------------------------------------------------------------------------

@test "ensure_initiative creates when absent and returns the new id" {
    export Q_RESP='{"data":{"initiatives":{"nodes":[]}}}'
    export M_RESP='{"data":{"initiativeCreate":{"success":true,"initiative":{"id":"init-new"}}}}'
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        graphql::query() { printf "%s" "$Q_RESP"; }
        graphql::mutate() { echo "MUTATE $1" >> "$CALLS"; printf "%s" "$M_RESP"; }
        reconcile::ensure_initiative "speckit-repo:r" "R" "body"
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "init-new" ]
    grep -q "initiativeCreate" "${CALLS}"
}

@test "ensure_initiative skips (no mutation) when name+description are unchanged" {
    local marker="<!-- speckit-id: speckit-repo:r -->"
    local desc
    desc="$(printf 'body\n\n%s' "${marker}")"
    export Q_RESP
    Q_RESP="$(jq -nc --arg d "${desc}" '{data:{initiatives:{nodes:[{id:"init-x",name:"R",description:$d}]}}}')"
    export M_RESP='{}'
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        graphql::query() { printf "%s" "$Q_RESP"; }
        graphql::mutate() { echo "MUTATE $1" >> "$CALLS"; printf "%s" "$M_RESP"; }
        reconcile::ensure_initiative "speckit-repo:r" "R" "body"
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "init-x" ]
    [ ! -s "${CALLS}" ]   # zero mutations — the zero-churn contract
}

@test "ensure_initiative updates when the description changed" {
    local marker="<!-- speckit-id: speckit-repo:r -->"
    local stale
    stale="$(printf 'OLD body\n\n%s' "${marker}")"
    export Q_RESP
    Q_RESP="$(jq -nc --arg d "${stale}" '{data:{initiatives:{nodes:[{id:"init-x","name":"R",description:$d}]}}}')"
    export M_RESP='{"data":{"initiativeUpdate":{"success":true}}}'
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        graphql::query() { printf "%s" "$Q_RESP"; }
        graphql::mutate() { echo "MUTATE $1" >> "$CALLS"; printf "%s" "$M_RESP"; }
        reconcile::ensure_initiative "speckit-repo:r" "R" "NEW body"
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "init-x" ]
    grep -q "initiativeUpdate" "${CALLS}"
}

# ---------------------------------------------------------------------------
# ensure_project
# ---------------------------------------------------------------------------

@test "ensure_project creates when absent and returns the new id" {
    export Q_RESP='{"data":{"team":{"projects":{"nodes":[]}}}}'
    export M_RESP='{"data":{"projectCreate":{"success":true,"project":{"id":"proj-new"}}}}'
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        graphql::query() { printf "%s" "$Q_RESP"; }
        graphql::mutate() { echo "MUTATE $1" >> "$CALLS"; printf "%s" "$M_RESP"; }
        reconcile::ensure_project "speckit-spec:007" "spec-007" "body" "team-uuid"
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "proj-new" ]
    grep -q "projectCreate" "${CALLS}"
}

@test "ensure_project skips (no mutation) when unchanged" {
    local marker="<!-- speckit-id: speckit-spec:007 -->"
    local desc
    desc="$(printf 'body\n\n%s' "${marker}")"
    export Q_RESP
    Q_RESP="$(jq -nc --arg d "${desc}" '{data:{team:{projects:{nodes:[{id:"proj-x",name:"spec-007",description:$d}]}}}}')"
    export M_RESP='{}'
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        graphql::query() { printf "%s" "$Q_RESP"; }
        graphql::mutate() { echo "MUTATE $1" >> "$CALLS"; printf "%s" "$M_RESP"; }
        reconcile::ensure_project "speckit-spec:007" "spec-007" "body" "team-uuid"
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "proj-x" ]
    [ ! -s "${CALLS}" ]
}
