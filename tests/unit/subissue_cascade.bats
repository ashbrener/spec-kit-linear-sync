#!/usr/bin/env bats
# tests/unit/subissue_cascade.bats — 013 lifecycle cascade (FR-001..FR-003).
# reconcile::_phase_state_key: terminal spec → done (override); non-terminal →
# checkbox ratio (subissue_state_key, unchanged); deterministic/idempotent.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
RECONCILE_SH="${SRC_ROOT}/src/reconcile.sh"

# Run _phase_state_key with subissue_state_key stubbed to a sentinel, so we can
# tell "cascade override" (done) apart from "checkbox-ratio path" (RATIO).
key_for() {  # <lifecycle_phase>
    run bash -c "
        source '${RECONCILE_SH}' 2>/dev/null || true
        reconcile::subissue_state_key() { printf 'RATIO\n'; }
        reconcile::_phase_state_key '$1' '/tmp/whatever-tasks.md' '1'
    "
}

@test "merged → done (override, ignores checkbox ratio)" {
    key_for merged
    [ "$status" -eq 0 ]
    [ "$output" = "done" ]
}

@test "ready_to_merge → done (override)" {
    key_for ready_to_merge
    [ "$output" = "done" ]
}

@test "implementing → checkbox ratio (non-terminal, unchanged)" {
    key_for implementing
    [ "$output" = "RATIO" ]
}

@test "specifying → checkbox ratio" {
    key_for specifying
    [ "$output" = "RATIO" ]
}

@test "empty/unknown lifecycle → checkbox ratio (3-arg back-compat)" {
    key_for ""
    [ "$output" = "RATIO" ]
}

@test "deterministic: merged resolves 'done' identically twice (idempotent)" {
    key_for merged; local a="$output"
    key_for merged; local b="$output"
    [ "$a" = "done" ] && [ "$b" = "done" ]
}

@test "sync_task_phase_subissues accepts a 4th lifecycle_phase arg + routes via _phase_state_key" {
    # Structural: the projector reads a 4th positional arg and the loop computes
    # state via the cascade helper (not subissue_state_key directly).
    run grep -c 'local lifecycle_phase="${4:-}"' "${RECONCILE_SH}"
    [ "$output" -eq 1 ]
    run grep -c 'reconcile::_phase_state_key "\$lifecycle_phase"' "${RECONCILE_SH}"
    [ "$output" -ge 1 ]
}
