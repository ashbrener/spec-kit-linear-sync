#!/usr/bin/env bats
# tests/unit/phase_header_grammar.bats — 013 broadened phase-header grammar.
# split_phase_header: digit run OR single letter (ordinal A→1…Z→26),
# separator-gated so words/multi-letter/glued tokens still near-miss.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
PARSER_SH="${SRC_ROOT}/src/parser.sh"

# Echo "<ok>|<idx>|<name>" for a single header line, via the shared prologue.
hdr() {  # <line>
    run bash -c "
        source '${PARSER_SH}'
        printf '%s\n' \"\$1\" | LC_ALL=C awk \"\$PARSER_PHASE_HEADER_AWK\"'
            { split_phase_header(\$0, o); printf \"%s|%s|%s\n\", o[\"ok\"], o[\"idx\"], o[\"name\"] }
        '
    " _ "$1"
}

@test "digit index: '## Phase 1: Setup' → ok,1,Setup (back-compat)" {
    hdr '## Phase 1: Setup'
    [ "$output" = "1|1|Setup" ]
}

@test "multi-digit index preserved: '## Phase 12 — X' → ok,12,X" {
    hdr '## Phase 12 — X'
    [ "$output" = "1|12|X" ]
}

@test "single letter A → ordinal 1: '## Phase A — Overlay'" {
    hdr '## Phase A — Overlay'
    [ "$output" = "1|1|Overlay" ]
}

@test "single letter B → ordinal 2" {
    hdr '## Phase B — Customers'
    [ "$output" = "1|2|Customers" ]
}

@test "lowercase letter c → ordinal 3 (case-insensitive)" {
    hdr '## Phase c — lower'
    [ "$output" = "1|3|lower" ]
}

@test "bare letter header (no separator/name): '## Phase A' → ok,1,(empty)" {
    hdr '## Phase A'
    [ "$output" = "1|1|" ]
}

@test "REJECT word index '## Phase one' (near-miss)" {
    hdr '## Phase one'
    [[ "$output" == 0\|* ]]
}

@test "REJECT multi-letter '## Phase AB nope' (near-miss)" {
    hdr '## Phase AB nope'
    [[ "$output" == 0\|* ]]
}

@test "REJECT digit glued to word '## Phase 1Setup' (near-miss)" {
    hdr '## Phase 1Setup'
    [[ "$output" == 0\|* ]]
}

@test "REJECT '## Phase :' (no index)" {
    hdr '## Phase :'
    [[ "$output" == 0\|* ]]
}
