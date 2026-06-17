#!/usr/bin/env bats
# tests/unit/spec_h1_name.bats — 012 H1 feature-name parse (FR-002 / D3).

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
PARSER_SH="${SRC_ROOT}/src/parser.sh"

setup() { TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-h1-XXXXXX")"; }
teardown() { [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"; }

h1() {  # <first-line>
    printf '%s\n\n**Status**: Draft\n' "$1" > "${TEST_TMP}/spec.md"
    run bash -c "source '${PARSER_SH}'; parser::spec_h1_name '${TEST_TMP}/spec.md'"
}

@test "extracts the trimmed feature name" {
    h1 '# Feature Specification: Faithful projection'
    [ "$status" -eq 0 ]
    [ "$output" = "Faithful projection" ]
}

@test "unfilled [FEATURE NAME] placeholder → empty" {
    h1 '# Feature Specification: [FEATURE NAME]'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "trailing whitespace is trimmed" {
    h1 '# Feature Specification: Author-Based Attribution   '
    [ "$output" = "Author-Based Attribution" ]
}

@test "missing heading → empty" {
    printf '## Overview\n\nNo H1 here.\n' > "${TEST_TMP}/spec.md"
    run bash -c "source '${PARSER_SH}'; parser::spec_h1_name '${TEST_TMP}/spec.md'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "missing file → empty (graceful)" {
    run bash -c "source '${PARSER_SH}'; parser::spec_h1_name '${TEST_TMP}/nope.md'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "only the FIRST matching heading is used" {
    printf '# Feature Specification: First Name\n# Feature Specification: Second\n' > "${TEST_TMP}/spec.md"
    run bash -c "source '${PARSER_SH}'; parser::spec_h1_name '${TEST_TMP}/spec.md'"
    [ "$output" = "First Name" ]
}
