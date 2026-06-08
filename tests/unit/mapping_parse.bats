#!/usr/bin/env bats
# tests/unit/mapping_parse.bats — spec 007, configurable mapping.
#
# Covers parsing the optional `mapping:` block from linear-config.yml and the
# resolved-mapping accessors reading explicit values; malformed enum values are
# config errors surfaced by config::mapping_validate (exit 2, fail-closed).

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
CONFIG_SH="${SRC_ROOT}/src/config.sh"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-mapping-parse-XXXXXX")"
    CFG="${TEST_TMP}/linear-config.yml"
}

teardown() {
    if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
        rm -rf "${TEST_TMP}"
    fi
}

# write_config <mapping-block-or-empty>
# Writes a parseable base config; the argument (if any) is appended verbatim
# under linear: as the `mapping:` block.
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

@test "mapping: block parses; resolved accessors read explicit per-level values" {
    write_config '  mapping:
    levels:
      spec:
        artifact: "Project"
        relationship_to_parent: "parent"
      phase:
        artifact: "Issue"
        relationship_to_parent: "parent"
      task:
        artifact: "sub-issue"
        relationship_to_parent: "parent"'
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::resolved_artifact spec; config::resolved_relationship spec; config::resolved_artifact phase; config::resolved_artifact task; config::resolved_relationship task"
    [ "${status}" -eq 0 ]
    [ "${lines[0]}" = "Project" ]
    [ "${lines[1]}" = "parent" ]
    [ "${lines[2]}" = "Issue" ]
    [ "${lines[3]}" = "sub-issue" ]
    [ "${lines[4]}" = "parent" ]
}

@test "mapping.l0 block parses; l0_field reads explicit values" {
    write_config '  mapping:
    l0:
      enabled: true
      artifact: "Milestone"
      on_absent: "degrade"
      source: "spec_input"'
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::l0_field enabled; config::l0_field on_absent; config::l0_field source"
    [ "${status}" -eq 0 ]
    [ "${lines[0]}" = "true" ]
    [ "${lines[1]}" = "degrade" ]
    [ "${lines[2]}" = "spec_input" ]
}

@test "config::l0_enabled reflects the parsed flag" {
    write_config '  mapping:
    l0:
      enabled: true'
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; if config::l0_enabled; then echo ON; else echo OFF; fi"
    [ "${status}" -eq 0 ]
    [ "${output}" = "ON" ]
}

@test "malformed artifact enum is a config error (exit 2)" {
    write_config '  mapping:
    levels:
      spec:
        artifact: "Bogus"
        relationship_to_parent: "parent"'
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::mapping_validate"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"mapping.levels.spec.artifact"* ]]
}

@test "malformed l0.on_absent enum is a config error (exit 2)" {
    write_config '  mapping:
    l0:
      enabled: true
      on_absent: "hard_fail"'
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::mapping_validate"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"mapping.l0.on_absent"* ]]
}
