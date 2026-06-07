#!/usr/bin/env bats
# tests/unit/seed_write_config.bats — unit tests for seed::write_config_uuids
#
# Regression cover for the duplicate-managed-key bug (#33, dup #40, #39):
#
#   The per-line YAML splicer in seed::write_config_uuids drops the children
#   of each managed UUID block (workflow_state_uuids / default_state_uuids /
#   agent_label_uuids) and re-emits a freshly rendered block exactly once.
#   The old code exited a skip block by FALLING THROUGH to a verbatim emit of
#   the current line. When that line was itself the next managed-block opener
#   (in the shipped config-template.yml `default_state_uuids:` directly
#   follows workflow_state_uuids's children, separated only by comments), the
#   stale zeroed opener was copied verbatim AND the dedicated seen-flag flush
#   re-appended the real block → a DUPLICATE YAML key. That duplicate made
#   linear-config.yml invalid strict YAML (prettier / yamllint reject it).
#
#   These tests splice against the REAL config-template.yml and assert each of
#   the three managed openers appears EXACTLY ONCE after the write-back, and
#   that the result has no duplicate keys. They fail on the pre-fix code and
#   pass on the fixed splicer.
#
# Sources src/seed.sh directly (it is source-safe: main() only runs under the
# `BASH_SOURCE == $0` guard). Compatible with bats-core 1.11.0.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
SEED_SH="${SRC_ROOT}/src/seed.sh"
TEMPLATE="${SRC_ROOT}/config-template.yml"

# Distinct non-zero UUIDs so we can also prove the rendered block carries the
# captured values rather than the template placeholders.
UUID_SPECIFYING="aaaaaaaa-0000-4000-8000-000000000001"
UUID_TODO="bbbbbbbb-0000-4000-8000-000000000001"
UUID_CLAUDE="cccccccc-0000-4000-8000-000000000001"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-seed-write-XXXXXX")"
    # Splice against a copy of the SHIPPED template so the positional ordering
    # that triggers the bug (default_state_uuids directly after
    # workflow_state_uuids's last child) is exercised exactly as installed.
    CONFIG="${TEST_TMP}/linear-config.yml"
    cp "${TEMPLATE}" "${CONFIG}"
}

teardown() {
    if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
        rm -rf "${TEST_TMP}"
    fi
}

# run_splice — source seed.sh, prime the captured-UUID arrays with a couple of
# real values, point SEED_CONFIG_PATH at the template copy, and run the
# write-back. Emits nothing on success; the config file is rewritten in place.
run_splice() {
    run bash -c '
        set -euo pipefail
        source "'"${SEED_SH}"'"
        SEED_CONFIG_PATH="'"${CONFIG}"'"
        SEED_WORKFLOW_UUIDS=([specifying]="'"${UUID_SPECIFYING}"'")
        SEED_DEFAULT_STATE_UUIDS=([todo]="'"${UUID_TODO}"'")
        SEED_AGENT_LABEL_UUIDS=([claude]="'"${UUID_CLAUDE}"'")
        seed::write_config_uuids
    '
}

# count_key <key> — number of times a 2-space-indented managed opener appears.
count_key() {
    grep -c "^[[:space:]]*$1:" "${CONFIG}"
}

@test "write_config_uuids: workflow_state_uuids appears exactly once" {
    run_splice
    [ "${status}" -eq 0 ]
    [ "$(count_key workflow_state_uuids)" -eq 1 ]
}

@test "write_config_uuids: default_state_uuids appears exactly once (the #33 victim)" {
    run_splice
    [ "${status}" -eq 0 ]
    # Pre-fix this is 2 (verbatim stale opener + seen-flag flush). Fixed: 1.
    [ "$(count_key default_state_uuids)" -eq 1 ]
}

@test "write_config_uuids: agent_label_uuids appears exactly once" {
    run_splice
    [ "${status}" -eq 0 ]
    [ "$(count_key agent_label_uuids)" -eq 1 ]
}

@test "write_config_uuids: a second write-back stays at exactly one of each (idempotent)" {
    run_splice
    [ "${status}" -eq 0 ]
    run_splice
    [ "${status}" -eq 0 ]
    [ "$(count_key workflow_state_uuids)" -eq 1 ]
    [ "$(count_key default_state_uuids)" -eq 1 ]
    [ "$(count_key agent_label_uuids)" -eq 1 ]
}

@test "write_config_uuids: captured UUIDs are written into the rendered blocks" {
    run_splice
    [ "${status}" -eq 0 ]
    grep -q "specifying:.*\"${UUID_SPECIFYING}\"" "${CONFIG}"
    grep -q "todo:.*\"${UUID_TODO}\"" "${CONFIG}"
    grep -q "claude:.*\"${UUID_CLAUDE}\"" "${CONFIG}"
}

@test "write_config_uuids: result is valid strict YAML with no duplicate keys" {
    run_splice
    [ "${status}" -eq 0 ]

    # Strict duplicate-key detection. PyYAML's default loader silently keeps
    # the last of duplicate keys, so we install a constructor that raises on
    # any duplicate mapping key — exactly what prettier / yamllint flag and
    # what the #39 report ("invalid linear-config.yml") was about.
    # Skipped (not failed) where PyYAML is unavailable so the suite stays
    # portable; the grep-count assertions above already pin the regression.
    if ! python3 -c 'import yaml' >/dev/null 2>&1; then
        skip "python3 + PyYAML not available for strict YAML parse"
    fi

    run python3 - "${CONFIG}" <<'PY'
import sys, yaml

class StrictLoader(yaml.SafeLoader):
    pass

def no_duplicates(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.constructor.ConstructorError(
                None, None, f"duplicate key: {key!r}", key_node.start_mark)
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping

StrictLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, no_duplicates)

with open(sys.argv[1]) as fh:
    yaml.load(fh, Loader=StrictLoader)
PY
    [ "${status}" -eq 0 ] || {
        echo "strict YAML parse failed (duplicate key or malformed):"
        echo "${output}"
        false
    }
}
