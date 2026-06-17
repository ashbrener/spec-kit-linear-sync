#!/usr/bin/env bats
# tests/integration/readable-titles.bats — 012 end-to-end title composition
# over a real fixture repo (filled-H1 + placeholder-H1 specs), gated by
# RUN_INTEGRATION_TESTS=1. Complements the unit suite by exercising the
# composer against on-disk specs and asserting byte-stable re-runs.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
load "${SRC_ROOT}/tests/helpers/integration-helpers.bash"
RECONCILE_SH="${SRC_ROOT}/src/reconcile.sh"

setup() {
    integration::skip_unless_enabled
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-titles-e2e-XXXXXX")"
    mkdir -p "${TEST_TMP}/specs/006-faithful-projection" "${TEST_TMP}/specs/001-fixtures"
    printf '# Feature Specification: Faithful projection\n\n**Input**: x\n' \
        > "${TEST_TMP}/specs/006-faithful-projection/spec.md"
    printf '# Feature Specification: [FEATURE NAME]\n\n**Input**: Establish the validated seed-data contract that is the single source of truth. Derived from context.\n' \
        > "${TEST_TMP}/specs/001-fixtures/spec.md"
}
teardown() { [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"; }

title() {  # <nnn> <slug>
    bash -c "source '${RECONCILE_SH}' 2>/dev/null || true
        reconcile::_compose_spec_title '$1' '${TEST_TMP}/specs/$1-$2' '$2'"
}

@test "filled-H1 spec → '<NNN> — <H1 name>'" {
    [ "$(title 006 faithful-projection)" = "006 — Faithful projection" ]
}

@test "placeholder-H1 spec → '<NNN> — <Input first sentence…>'" {
    run title 001 fixtures
    [[ "$output" == "001 — Establish the validated seed-data contract"* ]]
    [[ "$output" != *"[FEATURE NAME]"* ]]
}

@test "re-run is byte-stable (zero title churn)" {
    local a b
    a="$(title 006 faithful-projection)"
    b="$(title 006 faithful-projection)"
    [ "$a" = "$b" ]
}
