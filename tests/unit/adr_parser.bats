#!/usr/bin/env bats
# tests/unit/adr_parser.bats — spec 008, parser::adr_records.
#
# Covers the research.md ADR grammar (contracts/research-adr-grammar.md):
# explicit-id headings, titled-only, un-headed, missing sub-part, collision
# disambiguation, and graceful-empty. Output is one tab-separated record per
# ADR: <key>\t<title>\t<decision>\t<rationale>\t<alternatives>\t<source>.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
PARSER_SH="${SRC_ROOT}/src/parser.sh"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-adr-XXXXXX")"
    SPEC_DIR="${TEST_TMP}/specs/008-demo"
    mkdir -p "${SPEC_DIR}"
}

teardown() {
    [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"
}

records() { bash -c "source '${PARSER_SH}'; parser::adr_records '${SPEC_DIR}'"; }

@test "absent research.md emits nothing, returns 0" {
    run records
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "research.md with no ADR blocks emits nothing" {
    printf '# Research\n\nSome prose, no decisions.\n\n## Technical context\n\nNo bullets here.\n' > "${SPEC_DIR}/research.md"
    run records
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "explicit-id heading → key=heading id, fields parsed" {
    cat > "${SPEC_DIR}/research.md" <<'EOF'
## D1 — Default synthesis

- **Decision**: Use the alias layer.
  Second line of the decision.
- **Rationale**: It is constitutional.
- **Alternatives considered**: Rewrite the file (rejected).
EOF
    run records
    [ "${status}" -eq 0 ]
    [ "$(printf '%s' "${output}" | cut -f1)" = "D1" ]
    [ "$(printf '%s' "${output}" | cut -f2)" = "Default synthesis" ]
    [[ "$(printf '%s' "${output}" | cut -f3)" == "Use the alias layer.\nSecond line of the decision." ]]
    [ "$(printf '%s' "${output}" | cut -f6)" = "research.md" ]
}

@test "R<N> heading id is recognised too" {
    printf '## R7 — Some choice\n\n- **Decision**: Pick option A.\n' > "${SPEC_DIR}/research.md"
    run records
    [ "$(printf '%s' "${output}" | cut -f1)" = "R7" ]
}

@test "titled-only heading with bullets → key=title slug" {
    cat > "${SPEC_DIR}/research.md" <<'EOF'
## Per-level inheritance for partial blocks

- **Decision**: Only some levels is valid.
EOF
    run records
    [ "${status}" -eq 0 ]
    [ "$(printf '%s' "${output}" | cut -f1)" = "per-level-inheritance-for-partial-blocks" ]
}

@test "missing sub-part → empty field, not an error" {
    cat > "${SPEC_DIR}/research.md" <<'EOF'
## D5 — Narrative super-level

- **Decision**: Off by default.
- **Rationale**: Preserves the upgrade promise.
EOF
    run records
    [ "${status}" -eq 0 ]
    [ "$(printf '%s' "${output}" | cut -f1)" = "D5" ]
    [ -z "$(printf '%s' "${output}" | cut -f5)" ]   # alternatives empty
}

@test "two same-title un-headed/titled blocks get positional suffixes" {
    cat > "${SPEC_DIR}/research.md" <<'EOF'
## Trade-off

- **Decision**: First trade-off.

## Trade-off

- **Decision**: Second trade-off.
EOF
    run records
    [ "${status}" -eq 0 ]
    [ "$(printf '%s\n' "${output}" | sed -n 1p | cut -f1)" = "trade-off-1" ]
    [ "$(printf '%s\n' "${output}" | sed -n 2p | cut -f1)" = "trade-off-2" ]
}

@test "un-headed prose block (no heading) is still parsed" {
    printf -- '- **Decision**: Adopt the convention.\n- **Rationale**: It is simplest.\n' > "${SPEC_DIR}/research.md"
    run records
    [ "${status}" -eq 0 ]
    [ -n "${output}" ]
    [ "$(printf '%s' "${output}" | cut -f3)" = "Adopt the convention." ]
}

@test "a single base key gets no suffix" {
    printf '## D1 — Only one\n\n- **Decision**: Solo.\n' > "${SPEC_DIR}/research.md"
    run records
    [ "$(printf '%s' "${output}" | cut -f1)" = "D1" ]
}
