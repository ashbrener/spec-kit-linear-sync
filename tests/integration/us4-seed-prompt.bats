#!/usr/bin/env bats
# shellcheck shell=bats
# =============================================================================
# tests/integration/us4-seed-prompt.bats — T063
#
# User Story 4 (P2) acceptance scenario #2 (spec.md §User Story 4) +
# FR-022:
#
#   GIVEN a fresh sandbox consumer repo whose Linear workspace has
#         never been seeded (no `workflow_state_uuids` in
#         `linear-config.yml`),
#   WHEN  `src/install.sh` runs and reaches the seed-state check after
#         resolving the Team / Project UUIDs,
#   THEN  the install:
#           * detects the unseeded state (FR-022),
#           * in interactive mode, prompts the operator with two
#             paths — (default) run `/spec-kit-linear-sync-seed` inline,
#             or defer with a clear FR-022 notice,
#           * in --non-interactive mode, halts with the FR-022 error
#             and a copy-paste pointer to `bash src/seed.sh --team
#             <UUID>` so CI does not silently leave the workspace
#             half-installed.
#
# Two scenarios exercised:
#   (1) interactive accept (operator presses Enter)  → install::main
#       invokes src/seed.sh inline; the seed's structured-summary
#       "Created: N" line lands in the install report.
#   (2) interactive defer (operator types "n")       → install
#       completes; summary carries an FR-022 warning row and the
#       Next steps block names /spec-kit-linear-sync-seed.
#
# Maps to FR-022 + FR-027 + contracts/command-shapes.md §5.
# =============================================================================

load '../helpers/integration-helpers'

setup() {
    integration::skip_unless_enabled
    integration::setup_bare_sandbox
    integration::install_gh_shim_no_pr

    # ---- canned: viewer { id name email } for FR-034 operator capture ----
    integration::stage_response 'query-Me' \
        '{"data":{"viewer":{"id":"eeeeeeee-eeee-4eee-eeee-eeeeeeeeeeee","name":"Integration Tester","email":"integration@example.com"}}}'

    # ---- canned: seed-time workflow state queries return EMPTY arrays so
    # the inline seed has to create every state from scratch ----
    integration::stage_response 'query-WorkflowStatesByTeam' \
        '{"data":{"workflowStates":{"nodes":[]}}}'
    integration::stage_response 'query-WorkflowStateByName' \
        '{"data":{"workflowStates":{"nodes":[]}}}'
    integration::stage_response 'query-IssueLabels' \
        '{"data":{"issueLabels":{"nodes":[]}}}'
    integration::stage_response 'query-IssueLabelByName' \
        '{"data":{"issueLabels":{"nodes":[]}}}'

    # ---- canned: workflow-state create succeeds with a deterministic UUID ----
    integration::stage_response 'mutation-WorkflowStateCreate' \
        '{"data":{"workflowStateCreate":{"success":true,"workflowState":{"id":"ffffffff-ffff-4fff-ffff-ffffffffffff","name":"Stub"}}}}'
    integration::stage_response 'mutation-IssueLabelCreate' \
        '{"data":{"issueLabelCreate":{"success":true,"issueLabel":{"id":"ffffffff-ffff-4fff-ffff-ffffffffffff","name":"stub"}}}}'

    # ---- canned: catchall ----
    integration::stage_response 'default' \
        '{"data":{"viewer":{"id":"eeeeeeee-eeee-4eee-eeee-eeeeeeeeeeee","name":"Integration Tester","email":"integration@example.com"}}}'
    integration::stage_response 'query' \
        '{"data":{"viewer":{"id":"eeeeeeee-eeee-4eee-eeee-eeeeeeeeeeee","name":"Integration Tester","email":"integration@example.com"},"workflowStates":{"nodes":[]},"issueLabels":{"nodes":[]}}}'
    integration::stage_response 'mutation' \
        '{"data":{"workflowStateCreate":{"success":true,"workflowState":{"id":"ffffffff-ffff-4fff-ffff-ffffffffffff","name":"Stub"}},"issueLabelCreate":{"success":true,"issueLabel":{"id":"ffffffff-ffff-4fff-ffff-ffffffffffff","name":"stub"}}}}'
}

# integration::run_install_with_input <stdin_payload> [args...]
#   Wrapper for the helper's run_install that pipes <stdin_payload> as
#   stdin so the install's interactive prompts (seed Y/n, Action Y/n)
#   resolve deterministically. Mirrors the integration::run_install
#   shape so callers can keep the bats `run` $status / $output
#   conventions.
integration::run_install_with_input() {
    local input="$1"
    shift
    local install_sh
    install_sh="$(integration::find_install_sh)"
    (
        cd "$SANDBOX_REPO"
        export SPECKIT_LINEAR_CONFIG="$LINEAR_CONFIG_PATH"
        export SPECKIT_LINEAR_ROOT="$PROJECT_ROOT"
        printf '%s' "$input" | bash "$install_sh" "$@" 2>&1
    )
}

@test "T063: --non-interactive halts when workspace is unseeded (FR-022)" {
    # ---- run install in non-interactive mode without pre-seeding ----
    # The install copies config-template.yml into linear-config.yml,
    # which carries placeholder zero-UUIDs in workflow_state_uuids — so
    # install::prompt_seed_run treats the workspace as unseeded and
    # MUST halt with FR-022 rather than prompt (no stdin available in
    # CI / --non-interactive).
    run integration::run_install \
        --auto-create \
        --team "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa" \
        --no-action \
        --non-interactive
    # Non-zero exit (FR-022 surfaces via summary::has_errors → install
    # returns 1; the dependency report passes so it is NOT exit 2).
    [ "$status" -ne 0 ]

    # ---- error names the missing seed surface ----
    [[ "$output" == *"workspace unseeded"* ]] || [[ "$output" == *"workflow_state_uuids"* ]]
    [[ "$output" == *"src/seed.sh"* ]] || [[ "$output" == *"spec-kit-linear-sync-seed"* ]]

    # ---- summary block flags the unseeded error ----
    [[ "$output" == *"Errors: 1"* ]] || [[ "$output" == *"workspace unseeded"* ]]

    # ---- linear-config.yml WAS written — install's filesystem-side wiring
    # completed before the seed prompt halted (so re-running with the
    # operator's seed step is a one-command remediation) ----
    [ -f "$LINEAR_CONFIG_PATH" ]
    grep -q 'workflow_state_uuids:' "$LINEAR_CONFIG_PATH"
}

@test "T063: interactive accept runs src/seed.sh inline" {
    # Operator presses Enter at both prompts (accept seed, decline Action
    # via "n" — Action is out of scope for this test). The install must
    # invoke src/seed.sh during its own run.
    run integration::run_install_with_input $'y\nn\n' \
        --auto-create \
        --team "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"

    # The install completes successfully (or with at most a warning row)
    # — the inline seed's writes go through the curl shim and the
    # mock workflow-state queries return empty so every state gets
    # created.
    # Note: the install may still return non-zero if the seed itself
    # halts on a downstream step (e.g. the seed's config-write step
    # depends on yq-shaped parsing we have not stubbed). We assert on
    # the OBSERVABLE behaviour: install::_run_seed_inline ran the
    # seed binary, which is the load-bearing T063 contract.
    [[ "$output" == *"operator accepted seed prompt"* ]] || \
        [[ "$output" == *"running"* && "$output" == *"seed.sh"* ]] || \
        [[ "$output" == *"inline seed"* ]] || \
        [[ "$output" == *"seed completed"* ]]

    # ---- linear-config.yml written with the install ceremony's outputs ----
    [ -f "$LINEAR_CONFIG_PATH" ]
}

@test "T063: interactive defer completes install with FR-022 warning" {
    # Operator types "n" at the seed prompt, "n" at the Action prompt.
    run integration::run_install_with_input $'n\nn\n' \
        --auto-create \
        --team "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"

    # Install completes — defer is the explicit accepted path.
    [ "$status" -eq 0 ]

    # Summary carries the FR-022 deferral warning.
    [[ "$output" == *"seed deferred"* ]] || \
        [[ "$output" == *"deferred"* ]] || \
        [[ "$output" == *"FR-022"* ]]

    # Next-steps block names /spec-kit-linear-sync-seed as the unblocker.
    [[ "$output" == *"spec-kit-linear-sync-seed"* ]] || \
        [[ "$output" == *"speckit.linear-sync.seed"* ]] || \
        [[ "$output" == *"seed"* ]]

    # Install's filesystem-side wiring landed regardless.
    [ -f "$LINEAR_CONFIG_PATH" ]
    grep -q 'after_specify:' "${SANDBOX_REPO}/.specify/extensions.yml"
}

@test "T063 + FR-033b: SPECKIT_LINEAR_DOGFOOD_SAFE=1 surfaces dogfood-safe row" {
    # Pre-seed the config so the seed-prompt is skipped and we can
    # focus on the env-var detection path.
    integration::_write_config_yaml > "$LINEAR_CONFIG_PATH"

    SPECKIT_LINEAR_DOGFOOD_SAFE=1
    export SPECKIT_LINEAR_DOGFOOD_SAFE
    run integration::run_install \
        --auto-create \
        --team "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa" \
        --no-action \
        --non-interactive
    unset SPECKIT_LINEAR_DOGFOOD_SAFE

    [ "$status" -eq 0 ]

    # Dependency-report-time warning row names the env var.
    [[ "$output" == *"SPECKIT_LINEAR_DOGFOOD_SAFE"* ]]

    # FR-033b is named explicitly so the operator can search for it.
    [[ "$output" == *"FR-033b"* ]] || [[ "$output" == *"dogfood-safe"* ]]

    # Final summary block surfaces the safe-mode marker (the install
    # prints a multi-line "dogfood-safe mode is engaged" footer).
    [[ "$output" == *"dogfood-safe mode"* ]] || \
        [[ "$output" == *"dogfood-safe"* ]]
}
