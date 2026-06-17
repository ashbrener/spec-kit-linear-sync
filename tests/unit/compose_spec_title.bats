#!/usr/bin/env bats
# tests/unit/compose_spec_title.bats — 012 title composition: resolution
# order (H1 → Input → slug), first-sentence rule, length cap, determinism,
# migration, and graceful degradation (FR-001..FR-007 / SC-001..SC-006).

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
RECONCILE_SH="${SRC_ROOT}/src/reconcile.sh"

setup() { TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-title-XXXXXX")"; }
teardown() { [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"; }

# Write a fixture spec dir and echo the composed title.
compose() {  # <nnn> <slug> <h1-line> <input-value>
    local nnn="$1" slug="$2" h1="$3" input="$4"
    local d="${TEST_TMP}/specs/${nnn}-${slug}"
    mkdir -p "$d"
    {
        printf '%s\n\n' "$h1"
        [[ -n "$input" ]] && printf '**Input**: %s\n' "$input"
        printf '\n**Status**: Draft\n'
    } > "$d/spec.md"
    run bash -c "source '${RECONCILE_SH}' 2>/dev/null || true; reconcile::_compose_spec_title '${nnn}' '${d}' '${slug}'"
}

@test "H1 wins → '<NNN> — <name>'" {
    compose 006 faithful-projection '# Feature Specification: Faithful projection' ''
    [ "$status" -eq 0 ]
    [ "$output" = "006 — Faithful projection" ]
}

@test "placeholder H1 + Input → first sentence of Input" {
    compose 001 fixtures '# Feature Specification: [FEATURE NAME]' \
        'Establish the seed-data contract. Derived from context.'
    [ "$output" = "001 — Establish the seed-data contract" ]
}

@test "no H1 + no Input → slug (today's value), never empty" {
    compose 099 bare '## Overview' ''
    [ "$output" = "099-bare" ]
}

@test "never emits the [FEATURE NAME] placeholder" {
    compose 001 fixtures '# Feature Specification: [FEATURE NAME]' \
        'Some real input sentence here.'
    [[ "$output" != *"[FEATURE NAME]"* ]]
}

@test "long title is clean-boundary capped to one line with an ellipsis" {
    compose 001 fixtures '# Feature Specification: [FEATURE NAME]' \
        'Establish the validated internally consistent seed-data contract that is the single source of truth for the entire demo and every screen.'
    # within cap (80) + ends with ellipsis, no mid-word cut (ends on a word)
    [ "${#output}" -le 81 ]   # 80 chars + the 1 multibyte ellipsis char
    [[ "$output" == *"…" ]]
    [[ "$output" == "001 — Establish the validated"* ]]
}

@test "deterministic — same spec yields byte-identical title twice (SC-003)" {
    compose 006 faithful-projection '# Feature Specification: Faithful projection' ''
    local first="$output"
    compose 006 faithful-projection '# Feature Specification: Faithful projection' ''
    [ "$output" = "$first" ]
}

@test "migration: composed readable title differs from the old slug (SC-006)" {
    compose 006 faithful-projection '# Feature Specification: Faithful projection' ''
    # The old current title would be "006-faithful-projection"; the composed
    # title differs, so the existing current_title != title diff re-titles once.
    [ "$output" != "006-faithful-projection" ]
    [ "$output" = "006 — Faithful projection" ]
}

@test "_first_sentence: period-then-space, newline, and single-line squeeze" {
    run bash -c "source '${RECONCILE_SH}' 2>/dev/null || true
        reconcile::_first_sentence 'One sentence. Two sentence.'; echo '|'
        reconcile::_first_sentence \$'Line one\nLine two'; echo '|'
        reconcile::_first_sentence 'Trailing period.'; echo '|'"
    [[ "$output" == *"One sentence|"* ]]
    [[ "$output" == *"Line one Line two|"* ]]
    [[ "$output" == *"Trailing period|"* ]]
}
