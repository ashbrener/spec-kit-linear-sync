#!/usr/bin/env bats
# tests/unit/mapping_validate.bats — spec 007, configurable mapping.
#
# Covers the offline relationship-validation matrix (FR-006, FR-007, FR-013).
# The matrix is ARTIFACT-driven: the checklist sentinel pairs only with the
# checklist relationship; Project/Issue/sub-issue pair with parent/none subject
# to position rules. Every rejection hard-halts at config-load (exit 2, nothing
# written). The #17 spec-as-Project shape (which promotes task→sub-issue/parent)
# is accepted — proving the matrix is not hardcoded per level name.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
CONFIG_SH="${SRC_ROOT}/src/config.sh"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-mapping-validate-XXXXXX")"
    CFG="${TEST_TMP}/linear-config.yml"
}

teardown() {
    if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
        rm -rf "${TEST_TMP}"
    fi
}

write_config() {
    cat > "${CFG}" <<'EOF'
schema_version: 1

linear:
  team:
    id: "11111111-1111-1111-1111-111111111111"
  project:
    id: "22222222-2222-2222-2222-222222222222"
  labels:
    spec_prefix:      "speckit-spec:"
    repo_prefix:      "speckit-repo:"
    phase_prefix:     "task-phase:"
    lifecycle_prefix: "phase:"
    task_prefix:      "speckit-task:"
EOF
    if [[ -n "${1:-}" ]]; then
        printf '%s\n' "$1" >> "${CFG}"
    fi
}

validate() {
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::mapping_validate"
}

@test "the corrected #17 spec-as-Project shape validates (repo→Initiative > Project > Issue > sub-issue)" {
    write_config '  mapping:
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
        relationship_to_parent: "parent"'
    validate
    [ "${status}" -eq 0 ]
}

@test "Project nested under Project is rejected (Linear cannot build it; use Initiative)" {
    write_config '  mapping:
    levels:
      spec:
        artifact: "Project"
        relationship_to_parent: "parent"'
    validate
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"cannot nest under"* ]]
    [[ "${output}" == *"Initiative"* ]]
}

@test "Issue nested under an Initiative is rejected (needs a Project parent)" {
    write_config '  mapping:
    levels:
      repo:
        artifact: "Initiative"
        relationship_to_parent: "none"
      spec:
        artifact: "Issue"
        relationship_to_parent: "parent"'
    validate
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"cannot nest under"* ]]
}

@test "blocks as a hierarchy link is rejected (exit 2)" {
    write_config '  mapping:
    levels:
      spec:
        artifact: "Issue"
        relationship_to_parent: "blocks"'
    validate
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"blocks"* ]]
}

@test "relates as a hierarchy link is rejected (exit 2)" {
    write_config '  mapping:
    levels:
      phase:
        artifact: "sub-issue"
        relationship_to_parent: "relates"'
    validate
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"relates"* ]]
}

@test "parent on the top repo level (L0 off) is rejected (exit 2)" {
    write_config '  mapping:
    levels:
      repo:
        artifact: "Project"
        relationship_to_parent: "parent"'
    validate
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"repo"* ]]
}

@test "checklist artifact above the task level is rejected (exit 2)" {
    write_config '  mapping:
    levels:
      spec:
        artifact: "checklist"
        relationship_to_parent: "checklist"'
    validate
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"checklist"* ]]
}

@test "checklist artifact paired with a non-checklist relationship is rejected (exit 2)" {
    write_config '  mapping:
    levels:
      task:
        artifact: "checklist"
        relationship_to_parent: "parent"'
    validate
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"checklist"* ]]
}

@test "a non-top level with relationship none is rejected (exit 2)" {
    write_config '  mapping:
    levels:
      task:
        artifact: "sub-issue"
        relationship_to_parent: "none"'
    validate
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"task"* ]]
}

@test "repo parent IS allowed when L0 is enabled" {
    write_config '  mapping:
    l0:
      enabled: true
      artifact: "Initiative"
      on_absent: "degrade"
      source: "spec_input"
    levels:
      repo:
        artifact: "Project"
        relationship_to_parent: "parent"'
    validate
    [ "${status}" -eq 0 ]
}

@test "is_top_level: repo is top when L0 off, not top when L0 on" {
    write_config ''
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; if config::is_top_level repo; then echo TOP; else echo CHILD; fi"
    [ "${status}" -eq 0 ]
    [ "${output}" = "TOP" ]

    write_config '  mapping:
    l0:
      enabled: true
      artifact: "Initiative"
      on_absent: "degrade"
      source: "spec_input"'
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; if config::is_top_level repo; then echo TOP; else echo CHILD; fi"
    [ "${status}" -eq 0 ]
    [ "${output}" = "CHILD" ]
}

@test "mapping_is_default: true for a no-block config (dispatch → default path)" {
    write_config ''
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; if config::mapping_is_default; then echo DEFAULT; else echo MAPPED; fi"
    [ "${status}" -eq 0 ]
    [ "${output}" = "DEFAULT" ]
}

@test "mapping_is_default: false for the #17 spec-as-Project shape (dispatch → mapped path)" {
    write_config '  mapping:
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
        relationship_to_parent: "parent"'
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; if config::mapping_is_default; then echo DEFAULT; else echo MAPPED; fi"
    [ "${status}" -eq 0 ]
    [ "${output}" = "MAPPED" ]
}

@test "mapping_is_default: false when only the L0 super-level is enabled" {
    write_config '  mapping:
    l0:
      enabled: true
      artifact: "Initiative"
      on_absent: "degrade"
      source: "spec_input"'
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; if config::mapping_is_default; then echo DEFAULT; else echo MAPPED; fi"
    [ "${status}" -eq 0 ]
    [ "${output}" = "MAPPED" ]
}

@test "mapping_is_default: true for an explicit default block (alias equivalence)" {
    write_config '  mapping:
    levels:
      spec:
        artifact: "Issue"
        relationship_to_parent: "parent"
      task:
        artifact: "checklist"
        relationship_to_parent: "checklist"'
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; if config::mapping_is_default; then echo DEFAULT; else echo MAPPED; fi"
    [ "${status}" -eq 0 ]
    [ "${output}" = "DEFAULT" ]
}
