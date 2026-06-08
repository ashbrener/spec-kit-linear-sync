#!/usr/bin/env bats
# tests/unit/mapping_inherit.bats — spec 007, configurable mapping.
#
# Covers per-level inheritance (FR-005): a partial `mapping:` block specifying
# only some levels is valid; each unspecified level inherits the synthesized
# default for THAT level (not all-or-nothing, not cascading).

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
CONFIG_SH="${SRC_ROOT}/src/config.sh"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-mapping-inherit-XXXXXX")"
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
EOF
    if [[ -n "${1:-}" ]]; then
        printf '%s\n' "$1" >> "${CFG}"
    fi
}

resolve_all() {
    bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; \
        for L in repo spec phase task; do \
            printf '%s=%s/%s\n' \"\$L\" \"\$(config::resolved_artifact \$L)\" \"\$(config::resolved_relationship \$L)\"; \
        done; \
        printf 'l0=%s\n' \"\$(config::l0_field enabled)\""
}

@test "partial block overriding only spec inherits defaults for the rest" {
    write_config '  mapping:
    levels:
      spec:
        artifact: "Project"
        relationship_to_parent: "parent"'
    run resolve_all
    [ "${status}" -eq 0 ]
    [ "${lines[0]}" = "repo=Project/none" ]      # inherited default
    [ "${lines[1]}" = "spec=Project/parent" ]    # overridden
    [ "${lines[2]}" = "phase=sub-issue/parent" ] # inherited default
    [ "${lines[3]}" = "task=checklist/checklist" ] # inherited default
    [ "${lines[4]}" = "l0=false" ]               # inherited default
}

@test "partial block with only l0: keeps all four levels at default" {
    write_config '  mapping:
    l0:
      enabled: true
      artifact: "Milestone"
      on_absent: "degrade"
      source: "spec_input"'
    run resolve_all
    [ "${status}" -eq 0 ]
    [ "${lines[0]}" = "repo=Project/none" ]
    [ "${lines[1]}" = "spec=Issue/parent" ]
    [ "${lines[2]}" = "phase=sub-issue/parent" ]
    [ "${lines[3]}" = "task=checklist/checklist" ]
    [ "${lines[4]}" = "l0=true" ]
}

@test "partial block with only levels: leaves L0 off by default" {
    write_config '  mapping:
    levels:
      phase:
        artifact: "Issue"
        relationship_to_parent: "parent"'
    run resolve_all
    [ "${status}" -eq 0 ]
    [ "${lines[2]}" = "phase=Issue/parent" ]
    [ "${lines[4]}" = "l0=false" ]
}

@test "partial block validates clean" {
    write_config '  mapping:
    levels:
      spec:
        artifact: "Project"
        relationship_to_parent: "parent"'
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::mapping_validate && echo OK"
    [ "${status}" -eq 0 ]
    [ "${output}" = "OK" ]
}
