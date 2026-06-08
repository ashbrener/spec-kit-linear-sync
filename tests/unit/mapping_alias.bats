#!/usr/bin/env bats
# tests/unit/mapping_alias.bats — spec 007, configurable mapping.
#
# Covers the alias layer: an absent `mapping:` block synthesizes today's default
# (repo→Project, spec→Issue, phase→sub-issue, task→checklist, L0 off) from the
# existing binding keys, byte-for-byte back-compatible (FR-002); and an explicit
# default block resolves identically to the synthesized one (alias equivalence,
# US1 scenario 3, SC-001).

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
CONFIG_SH="${SRC_ROOT}/src/config.sh"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-mapping-alias-XXXXXX")"
    CFG="${TEST_TMP}/linear-config.yml"
}

teardown() {
    if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
        rm -rf "${TEST_TMP}"
    fi
}

# A minimal PRE-FEATURE config: no `mapping:` block at all.
write_prefeature_config() {
    cat > "${CFG}" <<'EOF'
schema_version: 1

linear:
  team:
    id: "11111111-1111-1111-1111-111111111111"
  project:
    id: "22222222-2222-2222-2222-222222222222"
EOF
}

# The same config WITH an explicit block spelling out today's default.
write_explicit_default_config() {
    cat > "${CFG}" <<'EOF'
schema_version: 1

linear:
  team:
    id: "11111111-1111-1111-1111-111111111111"
  project:
    id: "22222222-2222-2222-2222-222222222222"
  mapping:
    l0:
      enabled: false
      artifact: "Initiative"
      on_absent: "degrade"
      source: "spec_input"
    levels:
      repo:
        artifact: "Project"
        relationship_to_parent: "none"
      spec:
        artifact: "Issue"
        relationship_to_parent: "parent"
      phase:
        artifact: "sub-issue"
        relationship_to_parent: "parent"
      task:
        artifact: "checklist"
        relationship_to_parent: "checklist"
EOF
}

resolve_all() {
    # Echo the resolved mapping as a stable, comparable string.
    bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; \
        for L in repo spec phase task; do \
            printf '%s=%s/%s\n' \"\$L\" \"\$(config::resolved_artifact \$L)\" \"\$(config::resolved_relationship \$L)\"; \
        done; \
        printf 'l0=%s\n' \"\$(config::l0_field enabled)\""
}

@test "absent mapping synthesizes the frozen default" {
    write_prefeature_config
    run resolve_all
    [ "${status}" -eq 0 ]
    [ "${lines[0]}" = "repo=Project/none" ]
    [ "${lines[1]}" = "spec=Issue/parent" ]
    [ "${lines[2]}" = "phase=sub-issue/parent" ]
    [ "${lines[3]}" = "task=checklist/checklist" ]
    [ "${lines[4]}" = "l0=false" ]
}

@test "a pre-feature config loads + validates unchanged (no rewrite needed)" {
    write_prefeature_config
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::mapping_validate"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "explicit default block resolves identically to the synthesized default" {
    write_explicit_default_config
    run resolve_all
    [ "${status}" -eq 0 ]
    [ "${lines[0]}" = "repo=Project/none" ]
    [ "${lines[1]}" = "spec=Issue/parent" ]
    [ "${lines[2]}" = "phase=sub-issue/parent" ]
    [ "${lines[3]}" = "task=checklist/checklist" ]
    [ "${lines[4]}" = "l0=false" ]
}

@test "alias equivalence: synthesized and explicit-default resolutions match byte-for-byte" {
    write_prefeature_config
    synth="$(resolve_all)"
    write_explicit_default_config
    explicit="$(resolve_all)"
    [ "${synth}" = "${explicit}" ]
}

@test "default mapping validates clean" {
    write_prefeature_config
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::mapping_validate && echo OK"
    [ "${status}" -eq 0 ]
    [ "${output}" = "OK" ]
}
