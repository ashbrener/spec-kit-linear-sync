#!/usr/bin/env bats
# tests/unit/attribution_config.bats — 010 attribution config accessors +
# the gitignored authors-override loader. Asserts the default-OFF /
# absent-safe contract (SC-005) and override parsing (alias / null / absent).

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
CONFIG_SH="${SRC_ROOT}/src/config.sh"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-attrcfg-XXXXXX")"
    CFG="${TEST_TMP}/linear-config.yml"
}
teardown() {
    [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"
}

write_base_config() {  # [extra-attribution-yaml]
    {
        printf 'schema_version: 1\nconfig_version: 1\n\nlinear:\n'
        printf '  team:\n    id: "11111111-1111-1111-1111-111111111111"\n'
        printf '  project:\n    id: "22222222-2222-2222-2222-222222222222"\n'
        printf '  workflow_state_uuids:\n    merged: "aaaaaaaa-0001-0000-0000-000000000009"\n'
        if [[ -n "$1" ]]; then printf '%s\n' "$1"; fi
    } > "${CFG}"
}

@test "defaults: no attribution block → enabled OFF, label/assignee default ON" {
    write_base_config ""
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::attribution_enabled && echo ON || echo OFF"
    [ "$output" = "OFF" ]
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::attribution_label && echo ON || echo OFF"
    [ "$output" = "ON" ]
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::attribution_assignee && echo ON || echo OFF"
    [ "$output" = "ON" ]
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::attribution_subissue_label && echo ON || echo OFF"
    [ "$output" = "OFF" ]
}

@test "defaults: source order and authors path" {
    write_base_config ""
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::attribution_source_order"
    [ "$output" = "owner_line git_first_add" ]
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::authors_file_path"
    [ "$output" = ".specify/extensions/linear/linear-authors.local.yml" ]
}

@test "explicit values are parsed" {
    write_base_config "  attribution:
    enabled: true
    assignee: false
    label: true
    subissue_label: true"
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::attribution_enabled && echo ON || echo OFF"
    [ "$output" = "ON" ]
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::attribution_assignee && echo ON || echo OFF"
    [ "$output" = "OFF" ]
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::attribution_subissue_label && echo ON || echo OFF"
    [ "$output" = "ON" ]
}

@test "load_authors_override: alias entry + null non-member + absent" {
    write_base_config ""
    local ov="${TEST_TMP}/authors.local.yml"
    {
        printf 'schema_version: 1\nauthors:\n'
        printf '  alice@example.com:\n    handle: alice\n    linear_user_id: "abc-123"\n'
        printf '  contractor@example.com:\n    handle: contractor\n    linear_user_id: null\n'
    } > "$ov"
    run bash -c "
        source '${CONFIG_SH}'; config::load '${CFG}'
        config::load_authors_override '${ov}'
        echo \"handle=\${CONFIG_AUTHORS_HANDLE[alice@example.com]}\"
        echo \"uid=\${CONFIG_AUTHORS_USER_ID[alice@example.com]}\"
        echo \"cuid=[\${CONFIG_AUTHORS_USER_ID[contractor@example.com]}]\"
    "
    [[ "$output" == *"handle=alice"* ]]
    [[ "$output" == *"uid=abc-123"* ]]
    [[ "$output" == *"cuid=[null]"* ]]
}

@test "load_authors_override: absent file is a graceful no-op" {
    write_base_config ""
    run bash -c "source '${CONFIG_SH}'; config::load '${CFG}'; config::load_authors_override '${TEST_TMP}/nope.yml'; echo rc=\$?"
    [[ "$output" == *"rc=0"* ]]
}
