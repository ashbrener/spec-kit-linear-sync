#!/usr/bin/env bats
# tests/unit/title_scope.bats — 012 scope guard (FR-009 / contract I7).
# The readable-title composer must touch ONLY the spec Issue title, never
# sub-issue (`Phase N — <Name>`) titles or the speckit-spec:NNN identity label.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
RECONCILE_SH="${SRC_ROOT}/src/reconcile.sh"

@test "_compose_spec_title is invoked exactly once (the spec-Issue title site)" {
    run grep -c 'reconcile::_compose_spec_title "\$feature_number"' "${RECONCILE_SH}"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "sub-issue titles still use the literal 'Phase N — <Name>' form, not the composer" {
    # The sub-issue title is built as "Phase ${phase_index} — ${phase_name}";
    # it must NOT route through _compose_spec_title.
    run grep -c 'sub_title="Phase ' "${RECONCILE_SH}"
    [ "$output" -ge 1 ]
    # No _compose_spec_title call appears on a sub_title assignment line.
    run bash -c "grep -n 'sub_title=' '${RECONCILE_SH}' | grep -c '_compose_spec_title' || true"
    [ "$output" -eq 0 ]
}

@test "the speckit-spec:NNN identity label is unchanged (still feature-number based)" {
    run grep -c 'spec_label="speckit-spec:${feature_number}"' "${RECONCILE_SH}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "the composer never feeds the label or description path" {
    # _compose_spec_title output is assigned to `title`, not to spec_label or
    # any description/labels variable.
    run bash -c "grep -n '_compose_spec_title' '${RECONCILE_SH}' | grep -vE 'title=|# |reconcile::_compose_spec_title\(\)' | grep -c . || true"
    [ "$output" -eq 0 ]
}
