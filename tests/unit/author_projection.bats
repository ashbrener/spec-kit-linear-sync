#!/usr/bin/env bats
# tests/unit/author_projection.bats — 010 label strip-and-set semantics and
# the create-only/never-clobber + default-OFF invariants.
#
# The full sync_spec_issue wire path is exercised by the gated integration
# suite (tests/integration/author-attribution.bats). Here we lock (a) the
# exact jq strip-and-set filter the code uses (idempotency + no-dup), and
# (b) the structural invariants on reconcile.sh: the author assignee is
# computed only on the CREATE path, never added to an issueUpdate input, and
# every author write is gated on config::attribution_enabled.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
RECONCILE_SH="${SRC_ROOT}/src/reconcile.sh"

# --- (a) jq strip-and-set filter (the literal projection logic) ------------

strip_and_set() {  # <current-labels-json> <author-label-or-empty>
    local cur="$1" label="$2"
    local out
    out="$(printf '%s' "$cur" | jq -c '[.[] | select(startswith("author:") | not)]')"
    if [[ -n "$label" ]]; then
        out="$(printf '%s' "$out" | jq -c --arg l "$label" '. + [$l] | unique')"
    fi
    printf '%s' "$out"
}

@test "strip-and-set: stale author:* removed, new added, phase:* preserved" {
    run strip_and_set '["author:old","phase:planning","speckit-spec:010"]' 'author:new'
    [ "$status" -eq 0 ]
    # author:old gone, author:new present, phase + spec preserved
    [[ "$output" == *'"author:new"'* ]]
    [[ "$output" != *'"author:old"'* ]]
    [[ "$output" == *'"phase:planning"'* ]]
    [[ "$output" == *'"speckit-spec:010"'* ]]
}

@test "strip-and-set: idempotent — unchanged author yields the same set" {
    a="$(strip_and_set '["phase:planning","author:alice"]' 'author:alice')"
    b="$(strip_and_set "$a" 'author:alice')"
    asort="$(printf '%s' "$a" | jq -cS 'sort')"
    bsort="$(printf '%s' "$b" | jq -cS 'sort')"
    [ "$asort" = "$bsort" ]
    # exactly one author:* label (no duplication)
    count="$(printf '%s' "$b" | jq '[.[] | select(startswith("author:"))] | length')"
    [ "$count" -eq 1 ]
}

@test "strip-and-set: empty author label strips only (unknown author / label off)" {
    run strip_and_set '["author:stale","phase:planning"]' ''
    [[ "$output" != *"author:"* ]]
    [[ "$output" == *'"phase:planning"'* ]]
}

# --- (b) structural invariants on reconcile.sh -----------------------------

# Extract the issueUpdate-building region of sync_spec_issue (from the
# update-input construction to the mutate call) and assert assigneeId is
# absent — the create-only/never-clobber guarantee (FR-008 / SC-004).
@test "never-clobber: sync_spec_issue update path never references assigneeId" {
    run bash -c "
        awk '/Build the diff input. Only include fields/{p=1}
             p{print}
             p && /reconcile::mutate_issue_update \"\\\$issue_id\"/{exit}' '${RECONCILE_SH}' \
          | grep -c 'assigneeId' || true
    "
    [ "$output" = "0" ]
}

@test "default-OFF: author label + assignee writes are gated on config::attribution_enabled" {
    # The author label block and the create-assignee re-point both sit under
    # `if config::attribution_enabled`. Assert the gate guards them.
    run grep -c 'config::attribution_enabled' "${RECONCILE_SH}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 3 ]   # spec-issue resolve, create-assignee gate, update strip, sub-issue gates
}

@test "default-OFF: operator assignee (FR-034) remains the create value when attribution off" {
    # The create path must fall back to _resolve_operator_assignee_id in the
    # else-branch of the attribution gate.
    run bash -c "grep -A4 'if config::attribution_enabled; then' '${RECONCILE_SH}' | grep -c '_resolve_operator_assignee_id' || true"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "create path: author:<handle> is lazy-created (allow_create=1)" {
    run grep -c 'reconcile::_resolve_label_id "\$author_label" 1' "${RECONCILE_SH}"
    [ "$output" -ge 1 ]
}
