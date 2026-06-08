#!/usr/bin/env bats
# tests/unit/mapping_projection_helpers.bats — spec 007 projection leaf helpers.
#
# Covers the marker-based identity helpers and the idempotent Initiative/Project
# ensure_* leaf helpers (sub-increment 1 of the projection build). The GraphQL
# transport is stubbed (graphql::query/mutate overridden after sourcing) so the
# tests are hermetic and offline — they assert the helper's idempotency contract
# (create when absent, skip when unchanged, update when changed) and its return
# value, not the wire protocol (which graphql.bats covers).

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
export RECONCILE_SH="${SRC_ROOT}/src/reconcile.sh"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-proj-XXXXXX")"
    export TEST_TMP
    export CALLS="${TEST_TMP}/calls"
    : > "${CALLS}"
}

teardown() {
    if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
        rm -rf "${TEST_TMP}"
    fi
}

# ---------------------------------------------------------------------------
# Pure marker helpers
# ---------------------------------------------------------------------------

@test "mapping_id_marker composes the stable comment marker" {
    run bash -c "source '${RECONCILE_SH}' 2>/dev/null; reconcile::mapping_id_marker 'speckit-repo:my-repo'"
    [ "${status}" -eq 0 ]
    [ "${output}" = "<!-- speckit-id: speckit-repo:my-repo -->" ]
}

@test "mapping_id_extract round-trips an embedded marker" {
    run bash -c "source '${RECONCILE_SH}' 2>/dev/null; m=\$(reconcile::mapping_id_marker 'speckit-spec:007'); reconcile::mapping_id_extract \"prefix \$m suffix\""
    [ "${status}" -eq 0 ]
    [ "${output}" = "speckit-spec:007" ]
}

@test "mapping_id_extract returns empty when no marker is present" {
    run bash -c "source '${RECONCILE_SH}' 2>/dev/null; reconcile::mapping_id_extract 'just a plain description'"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "_compose_marked_description appends the marker and is idempotent" {
    run bash -c "source '${RECONCILE_SH}' 2>/dev/null
        d1=\$(reconcile::_compose_marked_description 'Body text' 'speckit-spec:007')
        d2=\$(reconcile::_compose_marked_description \"\$d1\" 'speckit-spec:007')
        [ \"\$d1\" = \"\$d2\" ] || { echo NOT_IDEMPOTENT; exit 1; }
        case \"\$d1\" in *'<!-- speckit-id: speckit-spec:007 -->'*) echo HAS_MARKER;; *) echo NO_MARKER;; esac"
    [ "${status}" -eq 0 ]
    [ "${output}" = "HAS_MARKER" ]
}

# ---------------------------------------------------------------------------
# ensure_initiative
# ---------------------------------------------------------------------------

@test "ensure_initiative creates when absent and returns the new id" {
    export Q_RESP='{"data":{"initiatives":{"nodes":[]}}}'
    export M_RESP='{"data":{"initiativeCreate":{"success":true,"initiative":{"id":"init-new"}}}}'
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        graphql::query() { printf "%s" "$Q_RESP"; }
        graphql::mutate() { echo "MUTATE $1" >> "$CALLS"; printf "%s" "$M_RESP"; }
        reconcile::ensure_initiative "speckit-repo:r" "R" "body"
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "init-new" ]
    grep -q "initiativeCreate" "${CALLS}"
}

@test "ensure_initiative skips (no mutation) when name+description are unchanged" {
    local marker="<!-- speckit-id: speckit-repo:r -->"
    local desc
    desc="$(printf 'body\n\n%s' "${marker}")"
    export Q_RESP
    Q_RESP="$(jq -nc --arg d "${desc}" '{data:{initiatives:{nodes:[{id:"init-x",name:"R",description:$d}]}}}')"
    export M_RESP='{}'
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        graphql::query() { printf "%s" "$Q_RESP"; }
        graphql::mutate() { echo "MUTATE $1" >> "$CALLS"; printf "%s" "$M_RESP"; }
        reconcile::ensure_initiative "speckit-repo:r" "R" "body"
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "init-x" ]
    [ ! -s "${CALLS}" ]   # zero mutations — the zero-churn contract
}

@test "ensure_initiative updates when the description changed" {
    local marker="<!-- speckit-id: speckit-repo:r -->"
    local stale
    stale="$(printf 'OLD body\n\n%s' "${marker}")"
    export Q_RESP
    Q_RESP="$(jq -nc --arg d "${stale}" '{data:{initiatives:{nodes:[{id:"init-x","name":"R",description:$d}]}}}')"
    export M_RESP='{"data":{"initiativeUpdate":{"success":true}}}'
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        graphql::query() { printf "%s" "$Q_RESP"; }
        graphql::mutate() { echo "MUTATE $1" >> "$CALLS"; printf "%s" "$M_RESP"; }
        reconcile::ensure_initiative "speckit-repo:r" "R" "NEW body"
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "init-x" ]
    grep -q "initiativeUpdate" "${CALLS}"
}

# ---------------------------------------------------------------------------
# ensure_project
# ---------------------------------------------------------------------------

@test "ensure_project creates when absent and returns the new id" {
    export Q_RESP='{"data":{"team":{"projects":{"nodes":[]}}}}'
    export M_RESP='{"data":{"projectCreate":{"success":true,"project":{"id":"proj-new"}}}}'
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        graphql::query() { printf "%s" "$Q_RESP"; }
        graphql::mutate() { echo "MUTATE $1" >> "$CALLS"; printf "%s" "$M_RESP"; }
        reconcile::ensure_project "speckit-spec:007" "spec-007" "body" "team-uuid"
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "proj-new" ]
    grep -q "projectCreate" "${CALLS}"
}

@test "ensure_project skips (no mutation) when unchanged" {
    local marker="<!-- speckit-id: speckit-spec:007 -->"
    local desc
    desc="$(printf 'body\n\n%s' "${marker}")"
    export Q_RESP
    Q_RESP="$(jq -nc --arg d "${desc}" '{data:{team:{projects:{nodes:[{id:"proj-x",name:"spec-007",description:$d}]}}}}')"
    export M_RESP='{}'
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        graphql::query() { printf "%s" "$Q_RESP"; }
        graphql::mutate() { echo "MUTATE $1" >> "$CALLS"; printf "%s" "$M_RESP"; }
        reconcile::ensure_project "speckit-spec:007" "spec-007" "body" "team-uuid"
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "proj-x" ]
    [ ! -s "${CALLS}" ]
}

# ---------------------------------------------------------------------------
# link_project_to_initiative
# ---------------------------------------------------------------------------

@test "link_project_to_initiative skips (no mutation) when already nested" {
    export Q_RESP='{"data":{"project":{"initiatives":{"nodes":[{"id":"init-1"}]}}}}'
    export M_RESP='{}'
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        graphql::query() { printf "%s" "$Q_RESP"; }
        graphql::mutate() { echo "MUTATE $1" >> "$CALLS"; printf "%s" "$M_RESP"; }
        reconcile::link_project_to_initiative "proj-1" "init-1"
    '
    [ "${status}" -eq 0 ]
    [ ! -s "${CALLS}" ]   # already linked → zero churn
}

@test "link_project_to_initiative adds the link when absent" {
    export Q_RESP='{"data":{"project":{"initiatives":{"nodes":[]}}}}'
    export M_RESP='{"data":{"projectUpdate":{"success":true}}}'
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        ARG_DRY_RUN=0
        graphql::query() { printf "%s" "$Q_RESP"; }
        graphql::mutate() { echo "MUTATE $2" >> "$CALLS"; printf "%s" "$M_RESP"; }
        reconcile::link_project_to_initiative "proj-1" "init-1"
    '
    [ "${status}" -eq 0 ]
    grep -q "addInitiativeIds" "${CALLS}"
}

# ---------------------------------------------------------------------------
# process_spec_mapped — #17 container orchestration (leaf helpers stubbed)
# ---------------------------------------------------------------------------

# Write a #17 spec-as-Project config and a minimal spec dir.
_write_17_config_and_spec() {
    CFG="${TEST_TMP}/linear-config.yml"
    cat > "${CFG}" <<'EOF'
schema_version: 1

linear:
  team:
    id: "11111111-1111-1111-1111-111111111111"
  project:
    id: "22222222-2222-2222-2222-222222222222"
  mapping:
    levels:
      repo:
        artifact: "Initiative"
        relationship_to_parent: "none"
      spec:
        artifact: "Project"
        relationship_to_parent: "parent"
      phase:
        artifact: "Issue"
        relationship_to_parent: "parent"
      task:
        artifact: "sub-issue"
        relationship_to_parent: "parent"
EOF
    SPEC_DIR="${TEST_TMP}/specs/007-demo"
    mkdir -p "${SPEC_DIR}"
    printf '# Spec\n\n**Input**: do a thing\n\n## Overview\n\nBody.\n' > "${SPEC_DIR}/spec.md"
    export CFG SPEC_DIR
}

@test "process_spec_mapped projects the #17 containers (Initiative + Project + link)" {
    _write_17_config_and_spec
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        config::load "${CFG}"
        reconcile::ensure_initiative() { echo "INIT $1" >> "$CALLS"; printf "init-1"; }
        reconcile::ensure_project() { echo "PROJ $1" >> "$CALLS"; printf "proj-1"; }
        reconcile::link_project_to_initiative() { echo "LINK $1 $2" >> "$CALLS"; }
        reconcile::render_spec_content_block() { printf "content"; }
        reconcile::_repo_slug() { printf "my-repo"; }
        reconcile::process_spec_mapped "${SPEC_DIR}"
    '
    [ "${status}" -eq 0 ]
    grep -q "INIT speckit-repo:my-repo" "${CALLS}"
    grep -q "PROJ speckit-spec:007" "${CALLS}"
    grep -q "LINK proj-1 init-1" "${CALLS}"
}

@test "process_spec_mapped skips (no writes) for a valid-but-unimplemented combo" {
    # L0 on + default levels → repo stays Project, spec stays Issue → not the
    # #17 chain → surfaced and skipped, nothing created.
    CFG="${TEST_TMP}/linear-config.yml"
    cat > "${CFG}" <<'EOF'
schema_version: 1

linear:
  team:
    id: "11111111-1111-1111-1111-111111111111"
  project:
    id: "22222222-2222-2222-2222-222222222222"
  mapping:
    l0:
      enabled: true
      artifact: "Initiative"
      on_absent: "degrade"
      source: "spec_input"
EOF
    SPEC_DIR="${TEST_TMP}/specs/007-demo"
    mkdir -p "${SPEC_DIR}"
    printf '# Spec\n\n## Overview\n\nBody.\n' > "${SPEC_DIR}/spec.md"
    export CFG SPEC_DIR
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        config::load "${CFG}"
        reconcile::ensure_initiative() { echo "INIT" >> "$CALLS"; printf "x"; }
        reconcile::ensure_project() { echo "PROJ" >> "$CALLS"; printf "x"; }
        reconcile::process_spec_mapped "${SPEC_DIR}"
    '
    [ "${status}" -eq 0 ]
    [ ! -s "${CALLS}" ]   # valid-but-unimplemented combo → nothing written
}

@test "process_spec_mapped projects phase Issues + task sub-issues under the Project" {
    _write_17_config_and_spec
    printf '## Phase 1: Setup\n- [ ] T001 Do the thing\n' > "${SPEC_DIR}/tasks.md"
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        config::load "${CFG}"
        reconcile::ensure_initiative() { printf "init-1"; }
        reconcile::ensure_project() { printf "proj-1"; }
        reconcile::link_project_to_initiative() { :; }
        reconcile::render_spec_content_block() { printf "content"; }
        reconcile::_repo_slug() { printf "my-repo"; }
        # Stub the within-project upsert to record (label, parent) and return a
        # deterministic id derived from the label so parent threading is visible.
        reconcile::_mapped_ensure_issue() { echo "MEI $1 parent=${6:-}" >> "$CALLS"; printf "issue-%s" "$1"; }
        reconcile::process_spec_mapped "${SPEC_DIR}"
    '
    [ "${status}" -eq 0 ]
    grep -q "MEI task-phase:1 parent=$" "${CALLS}"                              # phase → Issue, no parent
    grep -q "MEI speckit-task:T001 parent=issue-task-phase:1" "${CALLS}"        # task → sub-issue under the phase Issue
}

# ---------------------------------------------------------------------------
# _mapped_compute_drift — phase-Issue-aggregate backward-drift (FR-010)
# ---------------------------------------------------------------------------

@test "_mapped_compute_drift fires when a phase Issue is ahead of disk" {
    _write_17_config_and_spec
    # Disk: phase 1 has one UNCHECKED task → disk state = todo (ordinal 0).
    printf '## Phase 1: Setup\n- [ ] T001 Do the thing\n' > "${SPEC_DIR}/tasks.md"
    # Linear: the phase-1 Issue is `completed` (ordinal 2) → ahead → fire.
    export Q_RESP='{"data":{"issues":{"nodes":[{"id":"i1","state":{"type":"completed"},"labels":{"nodes":[{"name":"task-phase:1"}]}}]}}}'
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        config::load "${CFG}"
        graphql::query() { printf "%s" "$Q_RESP"; }
        v="$(reconcile::_mapped_compute_drift proj-1 "${SPEC_DIR}" 007 implementing)"
        reconcile::_drift_verdict_field "$v" fired
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "1" ]
}

@test "_mapped_compute_drift is silent when Linear matches disk (idempotent)" {
    _write_17_config_and_spec
    printf '## Phase 1: Setup\n- [ ] T001 Do the thing\n' > "${SPEC_DIR}/tasks.md"
    # Disk = todo; Linear phase-1 Issue is `unstarted` (ordinal 0) → equal → no fire.
    export Q_RESP='{"data":{"issues":{"nodes":[{"id":"i1","state":{"type":"unstarted"},"labels":{"nodes":[{"name":"task-phase:1"}]}}]}}}'
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        config::load "${CFG}"
        graphql::query() { printf "%s" "$Q_RESP"; }
        v="$(reconcile::_mapped_compute_drift proj-1 "${SPEC_DIR}" 007 implementing)"
        reconcile::_drift_verdict_field "$v" fired
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "0" ]
}

# ---------------------------------------------------------------------------
# _project_l0_initiative — L0 narrative super-level (US4)
# ---------------------------------------------------------------------------

_write_l0_config_and_spec() {
    CFG="${TEST_TMP}/linear-config.yml"
    cat > "${CFG}" <<'EOF'
schema_version: 1

linear:
  team:
    id: "11111111-1111-1111-1111-111111111111"
  project:
    id: "22222222-2222-2222-2222-222222222222"
  mapping:
    l0:
      enabled: true
      artifact: "Initiative"
      on_absent: "degrade"
      source: "spec_input"
EOF
    SPEC_DIR="${TEST_TMP}/specs/007-demo"
    mkdir -p "${SPEC_DIR}"
    printf '# Spec\n\n**Input**: build the thing\n\n## Overview\n\nBody.\n' > "${SPEC_DIR}/spec.md"
    export CFG SPEC_DIR
}

@test "_project_l0_initiative ensures the Initiative + links the repo Project when available" {
    _write_l0_config_and_spec
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        config::load "${CFG}"
        reconcile::_l0_initiative_available() { return 0; }
        reconcile::_repo_slug() { printf "my-repo"; }
        reconcile::_extract_input() { printf "build the thing"; }
        reconcile::ensure_initiative() { echo "INIT $1 narrative=$3" >> "$CALLS"; printf "init-1"; }
        reconcile::link_project_to_initiative() { echo "LINK $1 $2" >> "$CALLS"; }
        reconcile::_degrade_l0_onto_repo() { echo "DEGRADE" >> "$CALLS"; }
        reconcile::_project_l0_initiative "${SPEC_DIR}"
    '
    [ "${status}" -eq 0 ]
    grep -q "INIT speckit-repo:my-repo narrative=build the thing" "${CALLS}"   # narrative from Input only
    grep -q "LINK 22222222-2222-2222-2222-222222222222 init-1" "${CALLS}"      # bound repo Project nested
    ! grep -q "DEGRADE" "${CALLS}"
}

@test "_project_l0_initiative degrades onto the repo Project when Initiatives are unavailable" {
    _write_l0_config_and_spec
    run bash -c '
        source "${RECONCILE_SH}" 2>/dev/null
        reconcile::log() { :; }; summary::add() { :; }
        config::load "${CFG}"
        reconcile::_l0_initiative_available() { return 1; }   # plan-gated
        reconcile::_repo_slug() { printf "my-repo"; }
        reconcile::_extract_input() { printf "build the thing"; }
        reconcile::ensure_initiative() { echo "INIT" >> "$CALLS"; printf "init-1"; }
        reconcile::link_project_to_initiative() { echo "LINK" >> "$CALLS"; }
        reconcile::_degrade_l0_onto_repo() { echo "DEGRADE $1 narrative=$2" >> "$CALLS"; }
        reconcile::_project_l0_initiative "${SPEC_DIR}"
    '
    [ "${status}" -eq 0 ]
    grep -q "DEGRADE my-repo narrative=build the thing" "${CALLS}"   # folded onto repo, narrative preserved
    ! grep -q "^INIT" "${CALLS}"                                     # no Initiative created
    ! grep -q "^LINK" "${CALLS}"
}
