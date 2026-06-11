#!/usr/bin/env bats
# tests/unit/adr_comments.bats — spec 008, reconcile::sync_adr_comments.
#
# The idempotency state machine (create / skip / update-in-place) + graceful
# absence + the rendered-body parity shape. parser::adr_records runs for real
# over a research.md fixture; the comment query + create/update helpers are
# stubbed so the tests assert the orchestration, not the wire.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
export RECONCILE_SH="${SRC_ROOT}/src/reconcile.sh"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-adrc-XXXXXX")"
    export TEST_TMP
    export CALLS="${TEST_TMP}/calls"; : > "${CALLS}"
    export SPEC_DIR="${TEST_TMP}/specs/008-demo"
    mkdir -p "${SPEC_DIR}"
    cat > "${SPEC_DIR}/research.md" <<'EOF'
## D1 — Demo decision

- **Decision**: Adopt the demo approach.
- **Rationale**: It is simplest.
- **Alternatives considered**: The hard way (rejected).
EOF
}
teardown() { [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"; }

@test "create when absent → one comment with the marker + ADR layout" {
    export CBODY="${TEST_TMP}/cbody"
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        reconcile::query_existing_comment_body() { printf "null"; }
        reconcile::mutate_comment_create() { echo "CREATE" >> "$CALLS"; printf "%s" "$2" > "$CBODY"; }
        reconcile::mutate_comment_update() { echo "UPDATE" >> "$CALLS"; }
        reconcile::sync_adr_comments "issue-1" "${SPEC_DIR}"
    '
    [ "${status}" -eq 0 ]
    grep -q "CREATE" "${CALLS}"
    ! grep -q "UPDATE" "${CALLS}"
    grep -q "<!-- spec-kit-linear: adr 008-D1 -->" "${CBODY}"
    grep -q "ADR D1 — Demo decision" "${CBODY}"
    grep -q "Adopt the demo approach." "${CBODY}"
}

@test "graceful no-op when research.md is absent" {
    rm -f "${SPEC_DIR}/research.md"
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        reconcile::query_existing_comment_body() { echo "QUERY" >> "$CALLS"; printf "null"; }
        reconcile::mutate_comment_create() { echo "CREATE" >> "$CALLS"; }
        reconcile::sync_adr_comments "issue-1" "${SPEC_DIR}"
    '
    [ "${status}" -eq 0 ]
    [ ! -s "${CALLS}" ]
}

@test "idempotent: a second run with the same body skips (zero churn)" {
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        CAPTURED=""
        reconcile::query_existing_comment_body() { printf "null"; }
        reconcile::mutate_comment_create() { CAPTURED="$2"; }
        reconcile::mutate_comment_update() { :; }
        reconcile::sync_adr_comments "issue-1" "${SPEC_DIR}"
        # second run: the comment already exists with the byte-identical body
        reconcile::query_existing_comment_body() { jq -nc --arg b "$CAPTURED" "{id:\"c1\",body:\$b}"; }
        reconcile::mutate_comment_create() { echo "CREATE" >> "$CALLS"; }
        reconcile::mutate_comment_update() { echo "UPDATE" >> "$CALLS"; }
        reconcile::sync_adr_comments "issue-1" "${SPEC_DIR}"
    '
    [ "${status}" -eq 0 ]
    [ ! -s "${CALLS}" ]
}

@test "update-in-place when the existing body differs (no duplicate)" {
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        reconcile::query_existing_comment_body() { jq -nc "{id:\"c1\",body:\"<!-- spec-kit-linear: adr 008-D1 -->\nSTALE\"}"; }
        reconcile::mutate_comment_create() { echo "CREATE" >> "$CALLS"; }
        reconcile::mutate_comment_update() { echo "UPDATE $1" >> "$CALLS"; }
        reconcile::sync_adr_comments "issue-1" "${SPEC_DIR}"
    '
    [ "${status}" -eq 0 ]
    grep -q "UPDATE c1" "${CALLS}"
    ! grep -q "CREATE" "${CALLS}"
}

@test "parity: rendered body matches the documented ADR layout" {
    export CBODY="${TEST_TMP}/cbody"
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        reconcile::query_existing_comment_body() { printf "null"; }
        reconcile::mutate_comment_create() { printf "%s" "$2" > "$CBODY"; }
        reconcile::sync_adr_comments "issue-1" "${SPEC_DIR}"
    '
    [ "${status}" -eq 0 ]
    # marker first, then heading, Status/Source table, then the three sections.
    [ "$(sed -n 1p "${CBODY}")" = "<!-- spec-kit-linear: adr 008-D1 -->" ]
    grep -q "| \*\*Status\*\* | Accepted |" "${CBODY}"
    grep -q "research.md" "${CBODY}"
    grep -q "^\*\*Decision\*\*$" "${CBODY}"
    grep -q "^\*\*Rationale\*\*$" "${CBODY}"
    grep -q "^\*\*Alternatives considered\*\*$" "${CBODY}"
}

@test "missing sub-part omits its section from the body" {
    cat > "${SPEC_DIR}/research.md" <<'EOF'
## D2 — No alternatives here

- **Decision**: Just decide.
- **Rationale**: Because.
EOF
    export CBODY="${TEST_TMP}/cbody"
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        reconcile::query_existing_comment_body() { printf "null"; }
        reconcile::mutate_comment_create() { printf "%s" "$2" > "$CBODY"; }
        reconcile::sync_adr_comments "issue-1" "${SPEC_DIR}"
    '
    [ "${status}" -eq 0 ]
    grep -q "^\*\*Decision\*\*$" "${CBODY}"
    ! grep -q "Alternatives considered" "${CBODY}"
}
