#!/usr/bin/env bats
# shellcheck shell=bats
# =============================================================================
# tests/integration/us1-phase-header-nearmiss.bats — #34 near-miss warning
#
# Regression coverage for the silent-0-sub-issue bug (#34):
#
#   The phase-header parser is colon-only (`^## Phase [0-9]+:` in
#   src/parser.sh). A tasks.md whose headers use an em-dash delimiter
#   (`## Phase 1 — Setup`) — or a hyphen, or bare — matches the parser
#   NOTHING, so ZERO task-phase sub-issues are created with no other
#   diagnostic. The fix adds an explicit near-miss WARNING via
#   parser::phase_header_near_misses + reconcile.sh, making the silent
#   miss loud. This PR does NOT broaden the accepted grammar — headers
#   must still use `## Phase N:`.
#
# Scenario:
#
#   GIVEN a `specs/006-emdash-phases/` directory whose tasks.md has two
#         `## Phase N — <Name>` (em-dash) headers and a clean Linear
#         state (no Issues match speckit-spec:006),
#   WHEN  `src/reconcile.sh --spec 006` runs from the spec's feature
#         branch (FR-025 write-authority gate permits writes),
#   THEN  the reconciler:
#           * exits 0 (FR-024 — warnings never fail the run),
#           * emits the near-miss WARNING naming the expected
#             `## Phase N:` form, and
#           * creates ZERO task-phase sub-issues (grammar unchanged —
#             no mutation references a `Phase N — <Name>` sub-issue
#             title).
#
# Maps to #34, FR-005 (phase-header grammar — unchanged here), FR-024.
#
# Mock strategy mirrors us1-fresh-reconcile.bats: the default curl shim
# returns "no nodes" for locate queries and a fake-UUID payload for
# mutations. We assert on the summary text + the call log.
# =============================================================================

load '../helpers/integration-helpers'

setup() {
    integration::skip_unless_enabled
    integration::setup_sandbox '006-emdash-phases'
    integration::install_gh_shim_no_pr

    # Spec-issue locate → zero nodes (forces CREATE of the spec Issue).
    integration::stage_response 'query-LocateSpecIssue' \
        '{"data":{"issues":{"nodes":[]}}}'

    # Generic query fallback — empty so reconcile sees no existing state.
    integration::stage_response 'query' \
        '{"data":{"issues":{"nodes":[]},"issue":{"blocks":{"nodes":[]}}}}'

    # Mutations always succeed and echo a stable fake UUID.
    integration::stage_response 'mutation' \
        '{"data":{"issueCreate":{"success":true,"issue":{"id":"11111111-1111-4111-1111-111111111111","identifier":"ACM-1","title":"created"}},"issueUpdate":{"success":true,"issue":{"id":"22222222-2222-4222-2222-222222222222","identifier":"ACM-2","title":"updated","state":{"id":"cccccccc-0004-4ccc-cccc-cccccccccccc"}}}}}'

    integration::stage_response 'default' '{"data":{}}'
}

@test "us1-phase-header-nearmiss: em-dash headers emit the near-miss warning and create 0 sub-issues" {
    run integration::run_reconcile --spec 006

    # ---- exit code: warnings never fail the run (FR-024) ----
    [ "$status" -eq 0 ]

    # ---- the near-miss WARNING is surfaced in the summary ----
    # Distinctive substring from reconcile.sh's summary::add warned line.
    # (Fails on pre-fix code — no such warning existed.)
    [[ "$output" == *"speckit.linear summary"* ]]
    [[ "$output" == *"phase-like heading(s) not parsed"* ]]
    [[ "$output" == *"## Phase N:"* ]]

    # ---- ZERO task-phase sub-issues created (grammar unchanged) ----
    # The colon-only parser matches neither em-dash header, so no
    # sub-issue create mutation may reference a `Phase N — <Name>` title.
    # (The sub-issue title format the bridge constructs is `Phase N —
    # <Name>`; if the parser had wrongly accepted the em-dash header,
    # that exact string would appear in a create mutation body.)
    # NOTE: we grep the call log directly rather than via
    # integration::calls_containing — its grep -c emits a spurious extra
    # line on the zero-match path, which only matters for an `-eq 0` check.
    local phase1_calls phase2_calls
    phase1_calls="$(grep -cF 'Phase 1 — Setup' "${MOCK_LINEAR_STATE}/calls.log" || true)"
    [ "$phase1_calls" -eq 0 ] \
        || { echo "expected 0 mutations referencing 'Phase 1 — Setup' (em-dash header must NOT parse), got ${phase1_calls}" >&2; false; }

    phase2_calls="$(grep -cF 'Phase 2 — Foundational' "${MOCK_LINEAR_STATE}/calls.log" || true)"
    [ "$phase2_calls" -eq 0 ] \
        || { echo "expected 0 mutations referencing 'Phase 2 — Foundational' (em-dash header must NOT parse), got ${phase2_calls}" >&2; false; }
}
