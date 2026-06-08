#!/usr/bin/env bats
# tests/unit/config.bats — unit tests for src/config.sh
#
# Covers:
#   - happy path: every getter returns the right UUID
#   - missing file: config::load exits 2 with "file not found"
#   - missing required field: config::validate names the field
#   - malformed UUID: config::validate flags it with file:field
#   - workflow-state UUID lookup for every lifecycle phase
#   - default-state UUID lookup for todo|in_progress|done
#
# Compatible with bats-core 1.11.0. Sources src/config.sh directly.

# Resolve repo root from this file's location so the tests run no
# matter where bats is invoked from (`bats tests/unit/config.bats`
# from the repo root, or `cd tests && bats unit/config.bats`).
SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
CONFIG_SH="${SRC_ROOT}/src/config.sh"

# UUID fixtures — distinct so we can prove the right one comes back
# from each getter and not, e.g., a copy of the previous answer.
UUID_TEAM="11111111-1111-1111-1111-111111111111"
UUID_PROJECT="22222222-2222-2222-2222-222222222222"
UUID_SPECIFYING="aaaaaaaa-0001-0000-0000-000000000001"
UUID_CLARIFYING="aaaaaaaa-0001-0000-0000-000000000002"
UUID_PLANNING="aaaaaaaa-0001-0000-0000-000000000003"
UUID_TASKING="aaaaaaaa-0001-0000-0000-000000000004"
UUID_RED_TEAM="aaaaaaaa-0001-0000-0000-000000000005"
UUID_IMPLEMENTING="aaaaaaaa-0001-0000-0000-000000000006"
UUID_ANALYZING="aaaaaaaa-0001-0000-0000-000000000007"
UUID_READY="aaaaaaaa-0001-0000-0000-000000000008"
UUID_MERGED="aaaaaaaa-0001-0000-0000-000000000009"
UUID_TODO="bbbbbbbb-0002-0000-0000-000000000001"
UUID_IN_PROGRESS="bbbbbbbb-0002-0000-0000-000000000002"
UUID_DONE="bbbbbbbb-0002-0000-0000-000000000003"
UUID_AGENT_CLAUDE="cccccccc-0003-0000-0000-000000000001"
UUID_AGENT_CODEX="cccccccc-0003-0000-0000-000000000002"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-config-XXXXXX")"
    VALID_YAML="${TEST_TMP}/linear-config.yml"
    write_valid_config "${VALID_YAML}"
}

teardown() {
    if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
        rm -rf "${TEST_TMP}"
    fi
}

# write_valid_config <path>
# Drops a fully-populated linear-config.yml at <path>. Includes the
# optional default_state_uuids block so the post-analyze remediation
# getters are exercised on the happy path too.
write_valid_config() {
    local path="$1"
    cat > "${path}" <<EOF
schema_version: 1
config_version: 1

linear:
  workspace:
    name: "Test-Workspace"
    url_key: "test-workspace"
  team:
    id: "${UUID_TEAM}"
    key: "TST"
    name: "Test Team"
  project:
    id: "${UUID_PROJECT}"
    name: "test-project"
  workflow_state_uuids:
    specifying:     "${UUID_SPECIFYING}"
    clarifying:     "${UUID_CLARIFYING}"
    planning:       "${UUID_PLANNING}"
    tasking:        "${UUID_TASKING}"
    red_team:       "${UUID_RED_TEAM}"
    implementing:   "${UUID_IMPLEMENTING}"
    analyzing:      "${UUID_ANALYZING}"
    ready_to_merge: "${UUID_READY}"
    merged:         "${UUID_MERGED}"
  default_state_uuids:
    todo:        "${UUID_TODO}"
    in_progress: "${UUID_IN_PROGRESS}"
    done:        "${UUID_DONE}"
  agent_label_uuids:
    claude:      "${UUID_AGENT_CLAUDE}"
    codex:       "${UUID_AGENT_CODEX}"

sync:
  enabled: true
  idle_window_days: 30
  emit_summary: true

webhook:
  installed: false
  workflow_path: ".github/workflows/spec-kit-linear-sync.yml"
  secret_name: "LINEAR_API_TOKEN"

git_hooks:
  installed: false
  hooks:
    - post-checkout
    - post-commit
    - post-merge
EOF
}

# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

@test "config::load parses a valid file without error" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "config::get_team_id returns the team UUID" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_team_id"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_TEAM}" ]
}

@test "config::get_project_id returns the project UUID" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_project_id"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_PROJECT}" ]
}

@test "config::validate succeeds on a fully populated config" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::validate"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

# ---------------------------------------------------------------------------
# Workflow-state lookup for every lifecycle phase
# ---------------------------------------------------------------------------

@test "config::get_workflow_state_uuid specifying" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_workflow_state_uuid specifying"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_SPECIFYING}" ]
}

@test "config::get_workflow_state_uuid clarifying" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_workflow_state_uuid clarifying"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_CLARIFYING}" ]
}

@test "config::get_workflow_state_uuid planning" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_workflow_state_uuid planning"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_PLANNING}" ]
}

@test "config::get_workflow_state_uuid tasking" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_workflow_state_uuid tasking"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_TASKING}" ]
}

@test "config::get_workflow_state_uuid red_team" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_workflow_state_uuid red_team"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_RED_TEAM}" ]
}

@test "config::get_workflow_state_uuid implementing" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_workflow_state_uuid implementing"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_IMPLEMENTING}" ]
}

@test "config::get_workflow_state_uuid analyzing" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_workflow_state_uuid analyzing"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_ANALYZING}" ]
}

@test "config::get_workflow_state_uuid ready_to_merge" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_workflow_state_uuid ready_to_merge"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_READY}" ]
}

@test "config::get_workflow_state_uuid merged" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_workflow_state_uuid merged"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_MERGED}" ]
}

@test "config::get_workflow_state_uuid rejects an unknown phase" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_workflow_state_uuid bogus_phase"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"unknown lifecycle phase: bogus_phase"* ]]
}

# ---------------------------------------------------------------------------
# Default-state lookup (post-analyze remediation: todo/in_progress/done)
# ---------------------------------------------------------------------------

@test "config::get_default_state_uuid todo" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_default_state_uuid todo"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_TODO}" ]
}

@test "config::get_default_state_uuid in_progress" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_default_state_uuid in_progress"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_IN_PROGRESS}" ]
}

@test "config::get_default_state_uuid done" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_default_state_uuid done"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_DONE}" ]
}

@test "config::get_default_state_uuid rejects an unknown key" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_default_state_uuid blocked"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"unknown default-state key: blocked"* ]]
}

# ---------------------------------------------------------------------------
# Agent label UUID lookup (FR-036)
# ---------------------------------------------------------------------------

@test "config::get_agent_label_uuid returns claude UUID when present" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_agent_label_uuid claude"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_AGENT_CLAUDE}" ]
}

@test "config::get_agent_label_uuid returns codex UUID when present" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_agent_label_uuid codex"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_AGENT_CODEX}" ]
}

@test "config::get_agent_label_uuid returns empty when family absent from block" {
    # Block exists with codex but not gemini. Non-canonical family lookups
    # are not invalid — they're "no canonical UUID, fall back to lazy mint
    # by name at reconcile time", so the getter must return empty + 0.
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_agent_label_uuid gemini"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "config::get_agent_label_uuid returns empty when family argument is empty (graceful)" {
    # The reconciler calls this with an empty family when no env var
    # resolves. FR-036 graceful degradation: empty in ⇒ empty out, no halt.
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_agent_label_uuid ''"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "config::get_agent_label_uuid halts when block is missing AND family non-empty" {
    local no_agents="${TEST_TMP}/no-agent-block.yml"
    write_valid_config "${no_agents}"
    # Strip the agent_label_uuids block and its two children.
    awk '
        /^  agent_label_uuids:/ { in_block = 1; next }
        in_block && /^    / { next }
        { in_block = 0; print }
    ' "${no_agents}" > "${no_agents}.tmp"
    mv "${no_agents}.tmp" "${no_agents}"

    run bash -c "source '${CONFIG_SH}'; config::load '${no_agents}'; config::get_agent_label_uuid claude"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"linear.agent_label_uuids block is missing"* ]]
    [[ "${output}" == *"spec-kit-linear-seed"* ]]
}

@test "config::get_agent_label_uuid stays graceful when block is missing AND family is empty" {
    # The reconciler can run without ANY AI agent context (manual push from
    # a worker). In that case it calls the getter with empty family AND the
    # block may also be missing on a stale config — neither condition is a
    # failure on its own. Only the BOTH-non-empty AND BOTH-missing pairing
    # halts.
    local no_agents="${TEST_TMP}/no-agent-block-2.yml"
    write_valid_config "${no_agents}"
    awk '
        /^  agent_label_uuids:/ { in_block = 1; next }
        in_block && /^    / { next }
        { in_block = 0; print }
    ' "${no_agents}" > "${no_agents}.tmp"
    mv "${no_agents}.tmp" "${no_agents}"

    run bash -c "source '${CONFIG_SH}'; config::load '${no_agents}'; config::get_agent_label_uuid ''"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "config::get_agent_label_uuid rejects zero-argument call" {
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::get_agent_label_uuid"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"requires exactly one argument"* ]]
}

# ---------------------------------------------------------------------------
# Missing file → exit 2, actionable message
# ---------------------------------------------------------------------------

@test "config::load on a missing file exits 2 with a clear 'file not found' message" {
    local missing="${TEST_TMP}/does-not-exist.yml"
    run bash -c "source '${CONFIG_SH}'; config::load '${missing}'"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"file not found"* ]]
    [[ "${output}" == *"${missing}"* ]]
    # Operator hint must point at the install command.
    [[ "${output}" == *"spec-kit-linear-install"* ]]
}

@test "config::load with zero arguments exits 2" {
    run bash -c "source '${CONFIG_SH}'; config::load"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"requires exactly one argument"* ]]
}

# ---------------------------------------------------------------------------
# Missing required field → validate names it
# ---------------------------------------------------------------------------

@test "config::validate flags a missing linear.team.id" {
    local broken="${TEST_TMP}/missing-team.yml"
    write_valid_config "${broken}"
    # Drop the team.id line entirely.
    grep -v '    id: "'"${UUID_TEAM}"'"' "${broken}" > "${broken}.tmp"
    mv "${broken}.tmp" "${broken}"

    run bash -c "source '${CONFIG_SH}'; config::load '${broken}'; config::validate"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"linear.team.id: missing"* ]]
    [[ "${output}" == *"${broken}"* ]]
}

@test "config::validate flags a missing workflow_state_uuids.merged" {
    local broken="${TEST_TMP}/missing-merged.yml"
    write_valid_config "${broken}"
    grep -v "merged:         \"${UUID_MERGED}\"" "${broken}" > "${broken}.tmp"
    mv "${broken}.tmp" "${broken}"

    run bash -c "source '${CONFIG_SH}'; config::load '${broken}'; config::validate"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"linear.workflow_state_uuids.merged: missing"* ]]
    [[ "${output}" == *"spec-kit-linear-seed"* ]]
}

@test "config::validate flags a missing schema_version" {
    local broken="${TEST_TMP}/missing-schema.yml"
    write_valid_config "${broken}"
    grep -v '^schema_version: 1' "${broken}" > "${broken}.tmp"
    mv "${broken}.tmp" "${broken}"

    run bash -c "source '${CONFIG_SH}'; config::load '${broken}'; config::validate"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"schema_version"* ]]
    [[ "${output}" == *"missing"* ]]
}

# ---------------------------------------------------------------------------
# Malformed UUID → validate flags it with file:field location
# ---------------------------------------------------------------------------

@test "config::validate flags a malformed team UUID with file:field location" {
    local broken="${TEST_TMP}/malformed-team.yml"
    write_valid_config "${broken}"
    sed -i.bak "s|${UUID_TEAM}|not-a-uuid|" "${broken}"
    rm -f "${broken}.bak"

    run bash -c "source '${CONFIG_SH}'; config::load '${broken}'; config::validate"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"${broken}: linear.team.id: malformed UUID"* ]]
    [[ "${output}" == *"'not-a-uuid'"* ]]
}

@test "config::validate flags a malformed workflow-state UUID" {
    local broken="${TEST_TMP}/malformed-wfs.yml"
    write_valid_config "${broken}"
    sed -i.bak "s|${UUID_PLANNING}|deadbeef|" "${broken}"
    rm -f "${broken}.bak"

    run bash -c "source '${CONFIG_SH}'; config::load '${broken}'; config::validate"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"${broken}: linear.workflow_state_uuids.planning: malformed UUID"* ]]
}

@test "config::validate flags the zero-placeholder UUID as unresolved" {
    local broken="${TEST_TMP}/zero-team.yml"
    write_valid_config "${broken}"
    sed -i.bak "s|${UUID_TEAM}|00000000-0000-0000-0000-000000000000|" "${broken}"
    rm -f "${broken}.bak"

    run bash -c "source '${CONFIG_SH}'; config::load '${broken}'; config::validate"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"linear.team.id"* ]]
    [[ "${output}" == *"zero placeholder"* ]]
}

# ---------------------------------------------------------------------------
# Default-state block: optional in aggregate, all-or-nothing in detail
# ---------------------------------------------------------------------------

@test "config::validate accepts a config without the default_state_uuids block" {
    local minus_defaults="${TEST_TMP}/no-defaults.yml"
    write_valid_config "${minus_defaults}"
    # Strip the default_state_uuids block and its three children.
    awk '
        /^  default_state_uuids:/ { in_block = 1; next }
        in_block && /^    / { next }
        { in_block = 0; print }
    ' "${minus_defaults}" > "${minus_defaults}.tmp"
    mv "${minus_defaults}.tmp" "${minus_defaults}"

    run bash -c "source '${CONFIG_SH}'; config::load '${minus_defaults}'; config::validate"
    [ "${status}" -eq 0 ]
}

@test "config::validate rejects a partial default_state_uuids block" {
    local partial="${TEST_TMP}/partial-defaults.yml"
    write_valid_config "${partial}"
    # Remove only the `done:` child; keep `todo:` and `in_progress:`.
    grep -v "done: " "${partial}" > "${partial}.tmp"
    mv "${partial}.tmp" "${partial}"

    run bash -c "source '${CONFIG_SH}'; config::load '${partial}'; config::validate"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"linear.default_state_uuids.done: missing"* ]]
}

# ---------------------------------------------------------------------------
# Getter guards
# ---------------------------------------------------------------------------

@test "getters refuse to run before config::load" {
    run bash -c "source '${CONFIG_SH}'; config::get_team_id"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"no config loaded"* ]]
}

# ---------------------------------------------------------------------------
# spec 004 — config / identity split
# ---------------------------------------------------------------------------

# write_operator_local <path> <user_id> [name] [email]
# Drop a minimal operator-local identity file.
write_operator_local() {
    local path="$1" uid="$2" name="${3:-Local Operator}" email="${4:-local@example.com}"
    cat > "${path}" <<EOF
schema_version: 1
operator:
  user_id: "${uid}"
  name: "${name}"
  email: "${email}"
EOF
}

@test "FR-001: the committed config fixture carries no operator identity" {
    # The shareable binding fixture must have no operator.* keys, and all
    # existing getters/validate must still pass (FR-001 + FR-009).
    run grep -q 'operator:' "${VALID_YAML}"
    [ "${status}" -ne 0 ]
    run bash -c "source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::validate && config::get_team_id"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${UUID_TEAM}" ]
}

@test "FR-005: identity resolves from the operator-local file when no env is set" {
    local opfile="${TEST_TMP}/.specify/extensions/linear/linear-operator.local.yml"
    mkdir -p "$(dirname "${opfile}")"
    write_operator_local "${opfile}" "44444444-4444-4444-4444-444444444444"
    run bash -c "cd '${TEST_TMP}'; unset LINEAR_OPERATOR_USER_ID; source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::resolve_operator_user_id"
    [ "${status}" -eq 0 ]
    [ "${output}" = "44444444-4444-4444-4444-444444444444" ]
}

@test "FR-005: LINEAR_OPERATOR_USER_ID env wins over the operator-local file" {
    local opfile="${TEST_TMP}/.specify/extensions/linear/linear-operator.local.yml"
    mkdir -p "$(dirname "${opfile}")"
    write_operator_local "${opfile}" "44444444-4444-4444-4444-444444444444"
    run bash -c "cd '${TEST_TMP}'; export LINEAR_OPERATOR_USER_ID='55555555-5555-5555-5555-555555555555'; source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::resolve_operator_user_id"
    [ "${status}" -eq 0 ]
    [ "${output}" = "55555555-5555-5555-5555-555555555555" ]
}

@test "FR-011: no env and no local file resolves to empty (no halt)" {
    run bash -c "cd '${TEST_TMP}'; unset LINEAR_OPERATOR_USER_ID; source '${CONFIG_SH}'; config::load '${VALID_YAML}'; config::resolve_operator_user_id; echo \"status=\$?\""
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"status=0"* ]]
    # First line (the resolved id) must be empty.
    [ "$(printf '%s' "${output}" | head -n1)" = "" ]
}

@test "FR-005: resolve_operator_user_id NEVER reads identity from the committed config" {
    # Plant a committed-store value directly in CONFIG_VALUES (the legacy
    # leak shape) but supply NO env and an EMPTY operator-local store. The
    # resolver must return empty — it reads only env + CONFIG_OPERATOR_VALUES,
    # never CONFIG_VALUES (which is where the committed config lands).
    run bash -c "
        unset LINEAR_OPERATOR_USER_ID
        source '${CONFIG_SH}'
        config::load '${VALID_YAML}'
        # Simulate a stale committed-config identity key.
        CONFIG_VALUES[linear.operator.user_id]='deadbeef-dead-dead-dead-deaddeaddead'
        config::resolve_operator_user_id
    "
    [ "${status}" -eq 0 ]
    [ "$(printf '%s' "${output}" | head -n1)" = "" ]
}

@test "FR-007: legacy operator.* migrates to local file with exactly one notice" {
    local work="${TEST_TMP}/migrate"
    mkdir -p "${work}/.specify/extensions/linear"
    local cfg="${work}/.specify/extensions/linear/linear-config.yml"
    local opfile="${work}/.specify/extensions/linear/linear-operator.local.yml"
    write_valid_config "${cfg}"
    # Insert a legacy operator block under linear:.
    awk '/^  project:/ && !done { print "  operator:"; print "    user_id: \"33333333-3333-3333-3333-333333333333\""; print "    name: \"Legacy\""; print "    email: \"legacy@example.com\""; done=1 } { print }' \
        "${cfg}" > "${cfg}.tmp" && mv "${cfg}.tmp" "${cfg}"

    run bash -c "cd '${work}'; unset LINEAR_OPERATOR_USER_ID; source '${CONFIG_SH}'; config::load '.specify/extensions/linear/linear-config.yml' 2>&1; echo '---'; config::resolve_operator_user_id"
    [ "${status}" -eq 0 ]
    # Exactly one migration notice.
    [ "$(printf '%s\n' "${output}" | grep -c 'migrated operator identity')" -eq 1 ]
    # Identity is resolvable (moved to local file).
    [[ "${output}" == *"33333333-3333-3333-3333-333333333333"* ]]
    # The committed file no longer carries an operator block.
    run grep -q 'operator:' "${cfg}"
    [ "${status}" -ne 0 ]
    # The local file now exists.
    [ -f "${opfile}" ]
}

@test "FR-007: migration is idempotent — second load emits no notice" {
    local work="${TEST_TMP}/migrate2"
    mkdir -p "${work}/.specify/extensions/linear"
    local cfg="${work}/.specify/extensions/linear/linear-config.yml"
    write_valid_config "${cfg}"
    awk '/^  project:/ && !done { print "  operator:"; print "    user_id: \"33333333-3333-3333-3333-333333333333\""; done=1 } { print }' \
        "${cfg}" > "${cfg}.tmp" && mv "${cfg}.tmp" "${cfg}"

    # First load migrates (one notice).
    run bash -c "cd '${work}'; source '${CONFIG_SH}'; config::load '.specify/extensions/linear/linear-config.yml' 2>&1"
    [ "$(printf '%s\n' "${output}" | grep -c 'migrated operator identity')" -eq 1 ]
    # Second load (fresh process) must emit NO migration notice.
    run bash -c "cd '${work}'; source '${CONFIG_SH}'; config::load '.specify/extensions/linear/linear-config.yml' 2>&1"
    [ "$(printf '%s\n' "${output}" | grep -c 'migrated operator identity')" -eq 0 ]
}

@test "edge: legacy operator.* + pre-existing local file — local file wins, no clobber" {
    local work="${TEST_TMP}/migrate3"
    mkdir -p "${work}/.specify/extensions/linear"
    local cfg="${work}/.specify/extensions/linear/linear-config.yml"
    local opfile="${work}/.specify/extensions/linear/linear-operator.local.yml"
    write_valid_config "${cfg}"
    awk '/^  project:/ && !done { print "  operator:"; print "    user_id: \"33333333-3333-3333-3333-333333333333\""; done=1 } { print }' \
        "${cfg}" > "${cfg}.tmp" && mv "${cfg}.tmp" "${cfg}"
    # Pre-existing local file with a DIFFERENT (authoritative) identity.
    write_operator_local "${opfile}" "77777777-7777-7777-7777-777777777777"

    run bash -c "cd '${work}'; unset LINEAR_OPERATOR_USER_ID; source '${CONFIG_SH}'; config::load '.specify/extensions/linear/linear-config.yml' 2>&1; echo '---'; config::resolve_operator_user_id"
    [ "${status}" -eq 0 ]
    # The pre-existing local identity wins; legacy value is dropped.
    [[ "${output}" == *"77777777-7777-7777-7777-777777777777"* ]]
    [[ "${output}" != *"33333333-3333-3333-3333-333333333333"* ]]
    # Local file not clobbered.
    run grep -q '77777777-7777-7777-7777-777777777777' "${opfile}"
    [ "${status}" -eq 0 ]
}

@test "edge: malformed operator-local file surfaces a clear diagnostic (no silent failure)" {
    local work="${TEST_TMP}/malformed"
    mkdir -p "${work}/.specify/extensions/linear"
    local cfg="${work}/.specify/extensions/linear/linear-config.yml"
    write_valid_config "${cfg}"
    # Tab-indented operator-local file → the loader rejects tabs.
    printf 'operator:\n\tuser_id: "x"\n' > "${work}/.specify/extensions/linear/linear-operator.local.yml"
    run bash -c "cd '${work}'; source '${CONFIG_SH}'; config::load '.specify/extensions/linear/linear-config.yml'"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"tab character"* ]]
}
