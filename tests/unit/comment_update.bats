#!/usr/bin/env bats
# tests/unit/comment_update.bats — spec 008, reconcile::mutate_comment_update.
#
# The one new mutation: commentUpdate (update-in-place). Stubs the graphql
# transport; asserts dry-run logs without calling, and a real call issues
# commentUpdate with the body + handles success/failure.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
export RECONCILE_SH="${SRC_ROOT}/src/reconcile.sh"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-cu-XXXXXX")"
    export CALLS="${TEST_TMP}/calls"; : > "${CALLS}"
}
teardown() { [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"; }

@test "mutate_comment_update in dry-run logs and makes no call" {
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=1
        graphql::mutate() { echo "MUTATE" >> "$CALLS"; printf "{}"; }
        reconcile::mutate_comment_update "c1" "some body"
    '
    [ "${status}" -eq 0 ]
    [ ! -s "${CALLS}" ]
}

@test "mutate_comment_update issues commentUpdate with id+body on a real call" {
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        graphql::mutate() { echo "$1" > "$CALLS.mut"; echo "$2" > "$CALLS.vars"; printf "%s" "{\"data\":{\"commentUpdate\":{\"success\":true}}}"; }
        reconcile::mutate_comment_update "c1" "fresh body"
    '
    [ "${status}" -eq 0 ]
    grep -q "commentUpdate" "${CALLS}.mut"
    [ "$(jq -r .id "${CALLS}.vars")" = "c1" ]
    [ "$(jq -r .input.body "${CALLS}.vars")" = "fresh body" ]
}

@test "mutate_comment_update fails closed when success != true" {
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }; reconcile::promote_exit() { :; }
        ARG_DRY_RUN=0
        graphql::mutate() { printf "%s" "{\"data\":{\"commentUpdate\":{\"success\":false}}}"; }
        reconcile::mutate_comment_update "c1" "body"
    '
    [ "${status}" -ne 0 ]
}
