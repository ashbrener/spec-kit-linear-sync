#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016
# ^^^ Every GraphQL query/mutation string in this file uses single quotes so
#     `$variable` tokens remain literal — those are GraphQL variable references
#     resolved server-side, NOT bash expansions. Suppressing SC2016 file-wide
#     mirrors the convention in src/reconcile.sh and keeps the contract
#     readable.
# =============================================================================
# src/seed.sh — one-shot Linear workspace seeder (Layer D, install-time helper).
#
# Implements User Story 4 (P2 — "One-shot install and workspace seed") and the
# seed-time portion of `contracts/linear-graphql-mutations.md` §2. Materialises
# every Linear primitive the bridge needs at runtime that does NOT mint itself
# lazily during reconcile:
#
#   * Nine custom workflow states on the consumer team (FR-021, FR-032),
#     created via the `workflowStateCreate` GraphQL mutation because the live
#     MCP catalogue has no equivalent tool (Capability 8 in the runtime probe).
#   * Eighteen workspace-scoped issue labels — `phase:*` and `task-phase:*` —
#     created via `issueLabelCreate` GraphQL because hooks / non-AI paths have
#     no MCP session (Principle VI: keys-at-the-edges).
#
# After the writes settle, the script captures every returned UUID and writes
# the resolved IDs back into the consumer repo's
# `.specify/extensions/linear/linear-config.yml`. The two captured maps are:
#
#   * `linear.workflow_state_uuids` — 9 keys, matching the lifecycle phases
#     (specifying, clarifying, planning, tasking, red_team, implementing,
#     analyzing, ready_to_merge, merged). Driven by FR-032.
#   * `linear.default_state_uuids` — 3 keys (todo, in_progress, done), captured
#     from the team's stock workflow states so task-phase sub-issues per FR-005
#     can carry a Todo / In Progress / Done state without re-creating that
#     palette.
#
# The seed itself is idempotent (per Principle II and FR-021 — "safe to
# re-run"): every create is preceded by an existence query, and a re-run
# against an already-seeded workspace observably emits zero `created` events
# and produces the same `linear-config.yml` byte-for-byte.
#
# -----------------------------------------------------------------------------
# Constitutional alignment
# -----------------------------------------------------------------------------
# Principle V (UUID-based binding) — every Linear identifier we capture is
#   stored as a UUID in the per-repo config file. Lookups are never by name.
# Principle VI (OAuth-first, keys-at-the-edges) — this is one of the two paths
#   that legitimately uses LINEAR_API_KEY (the other is the GitHub Action). The
#   key never leaves graphql.sh's process; this script just calls into it.
# Principle VIII (observable failure) — every create/skip/error is funnelled
#   through `summary::*` and rendered in the final structured block. The
#   script never appears to succeed when it has silently dropped work.
#
# -----------------------------------------------------------------------------
# CLI surface (per contracts/command-shapes.md §4)
# -----------------------------------------------------------------------------
#   src/seed.sh [--team UUID] [--scope workspace|team] [--dry-run]
#               [--workspace-only] [--help]
#
# Exit codes (matching the rest of the bridge):
#   0  success (possibly with warnings)
#   1  transient failure (5xx after retry, rate-limit exhaustion). Re-run.
#   2  workspace-level config error (FR-022) — missing config, malformed UUIDs,
#      no team resolvable from config + CLI override.
#   3  transport failure across the board (Linear unreachable; nothing written).
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Module sourcing. Order matches src/reconcile.sh so a single shellcheck pass
# behaves identically across both entrypoints. graphql.sh + summary.sh are
# load-bearing; config.sh's getters are only used when we have an already-
# parsed config to extract `linear.team.id` from (the seed step's main input
# besides the API key).
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./config.sh disable=SC1091
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./graphql.sh disable=SC1091
source "${SCRIPT_DIR}/graphql.sh"
# shellcheck source=./summary.sh disable=SC1091
source "${SCRIPT_DIR}/summary.sh"

# -----------------------------------------------------------------------------
# Module constants.
# -----------------------------------------------------------------------------

# Default config path. Resolved relative to PWD (the consumer repo's root) so
# the same script binary serves every consumer repo's invocation. Matches the
# convention in reconcile.sh.
readonly SEED_CONFIG_PATH_DEFAULT=".specify/extensions/linear/linear-config.yml"

# Path of the template the seed copies from when the consumer repo has not yet
# materialised its `linear-config.yml`. The template is checked into the
# extension itself (committed as `config-template.yml` at the repo root, and
# also under `.specify/extensions/linear/` after `specify extension add
# linear`). The fallback search order below covers both.
readonly SEED_TEMPLATE_BASENAME="config-template.yml"

# -----------------------------------------------------------------------------
# CLI-flag globals — populated by seed::parse_args.
# -----------------------------------------------------------------------------
declare -g ARG_TEAM_OVERRIDE=""        # UUID or empty
declare -g ARG_DRY_RUN=0               # 0|1
declare -g ARG_WORKSPACE_ONLY=0        # 0|1 — skip the config.yml write
declare -g ARG_SEED_SCOPE=""           # workspace|team|"" (unset → resolve)
declare -g SEED_CONFIG_PATH=""         # populated after parse_args

# Resolved seed scope (spec 005, FR-005). Populated by seed::resolve_scope
# in main(); one of `workspace` or `team`. In `team` scope label creation
# passes teamId so a sub-team owner can seed without workspace-admin.
declare -g SEED_SCOPE="team"

# Could-not-provision tracker (spec 005, FR-011). Names of PERSISTED
# resources (workflow states / default states / agent labels) that could
# be neither created (no permission) nor adopted (not present). Surfaced
# as a single actionable listing at end-of-run so an admin knows exactly
# what to provision once. Keyed by a human label; value is unused.
declare -gA SEED_UNRESOLVED=()

# Aggregate exit-code tracker — monotonic promotion to higher severities.
declare -g SEED_EXIT_CODE=0

# -----------------------------------------------------------------------------
# Workflow-state catalogue (T058).
#
# Tab-separated rows: <lifecycle_key>\t<name>\t<type>\t<color>\t<position>.
# Order matches the position column so the array index is the de facto seed
# order. Names + colors + positions are locked by the task brief — changing
# any value here changes the operator-visible Linear UI without a constitution
# amendment, so don't.
# -----------------------------------------------------------------------------
readonly -a SEED_WORKFLOW_STATES=(
    $'specifying\tSpecifying\tunstarted\t#6B7280\t1'
    $'clarifying\tClarifying\tstarted\t#F59E0B\t2'
    $'planning\tPlanning\tstarted\t#3B82F6\t3'
    $'tasking\tTasking\tstarted\t#8B5CF6\t4'
    $'red_team\tRed-team\tstarted\t#EF4444\t5'
    $'implementing\tImplementing\tstarted\t#10B981\t6'
    $'analyzing\tAnalyzing\tstarted\t#06B6D4\t7'
    $'ready_to_merge\tReady-to-merge\tstarted\t#84CC16\t8'
    $'merged\tMerged\tcompleted\t#22C55E\t9'
)

# -----------------------------------------------------------------------------
# Label catalogue (T059).
#
# Two families — `phase:*` (one per lifecycle phase) and `task-phase:N`
# (covering up to 9 task phases per spec, per the task brief). All are
# workspace-scoped (the workspace-scope flag is set by passing teamId=null to
# the create mutation). The `speckit-spec:NNN` family is deliberately NOT in
# this list — those are minted lazily by reconcile.sh per spec, not seeded.
# -----------------------------------------------------------------------------
readonly -a SEED_PHASE_LABELS=(
    "phase:specifying"
    "phase:clarifying"
    "phase:planning"
    "phase:tasking"
    "phase:red_team"
    "phase:implementing"
    "phase:analyzing"
    "phase:ready_to_merge"
    "phase:merged"
)
readonly -a SEED_TASK_PHASE_LABELS=(
    "task-phase:1"
    "task-phase:2"
    "task-phase:3"
    "task-phase:4"
    "task-phase:5"
    "task-phase:6"
    "task-phase:7"
    "task-phase:8"
    "task-phase:9"
)

# Agent label family (FR-036). Sticky workspace-scoped labels identifying
# which AI agent ran the reconcile. v1 ships the two upstream-supported
# AI hosts; unrecognised agents fall back to `agent:<lowercased-first-word>`
# at reconcile time and the bridge mints those labels lazily. Captured
# UUIDs land in `linear-config.yml.linear.agent_label_uuids` keyed by
# family name (`claude`, `codex`).
#
# Tab-separated rows: <family>\t<label_name>. Family is the dictionary key;
# label_name is what Linear stores. Color choice: a distinguishable teal
# (#14B8A6) signals "system label, agent provenance" — adjacent in palette
# to the existing analyzing/red_team hues without colliding.
readonly -a SEED_AGENT_LABELS=(
    $'claude\tagent:claude'
    $'codex\tagent:codex'
)
readonly SEED_AGENT_LABEL_COLOR="#14B8A6"

# Default-state hunt table (FR-005, contracts §4.3). Tab-separated rows:
# <key>\t<expected_name>\t<expected_type>. We probe by name first (the common
# stock-Linear-team case where the names match exactly) and fall back to the
# first state whose type matches when the name doesn't line up — operators
# sometimes rename "Todo" → "Backlog" without changing the type.
readonly -a SEED_DEFAULT_STATE_LOOKUPS=(
    $'todo\tTodo\tunstarted'
    $'in_progress\tIn Progress\tstarted'
    $'done\tDone\tcompleted'
)

# Module-level capture buffers — populated by the create / discover paths and
# consumed by the config-write step. Bash 4+ associative arrays (Principle: we
# already require bash 4 elsewhere; macOS 3.2 is explicitly out of scope per
# plan.md Technical Context).
declare -gA SEED_WORKFLOW_UUIDS=()         # lifecycle_key → UUID
declare -gA SEED_DEFAULT_STATE_UUIDS=()    # todo|in_progress|done → UUID
# FR-036: per-family agent label UUIDs (claude, codex). Written back to
# linear-config.yml.linear.agent_label_uuids so reconcile.sh can stamp
# the running agent's family label onto every Issue / sub-issue it touches.
declare -gA SEED_AGENT_LABEL_UUIDS=()      # claude|codex → UUID
# SEED_LABEL_UUIDS is populated for diagnostics / future use (label UUIDs are
# not written to linear-config.yml because reconcile.sh looks labels up by
# name). The shellcheck SC2034 disable below is intentional — the array
# exists to surface "what labels does the workspace now hold" to anyone who
# wants to source seed.sh as a library, even though main() itself never
# reads it back out.
# shellcheck disable=SC2034
declare -gA SEED_LABEL_UUIDS=()            # label_name → UUID (diagnostics)

# -----------------------------------------------------------------------------
# seed::usage
#   Print operator-facing usage to stderr.
# -----------------------------------------------------------------------------
seed::usage() {
    cat >&2 <<'EOF'
Usage: seed.sh [--team UUID] [--scope workspace|team] [--dry-run]
               [--workspace-only] [--help]

One-shot Linear seed. Creates the 9 custom lifecycle workflow states +
the bridge's labels, captures every UUID, and writes them back into
.specify/extensions/linear/linear-config.yml.

A non-admin / sub-team owner can seed in `team` scope (the default):
labels are created scoped to the team (not workspace-wide), so no
workspace-admin permission is required. When a create is not permitted,
seed auto-falls-back to ADOPTING an already-existing state/label by name
and capturing its UUID — requiring zero create permission.

Options:
  --team UUID       Override the team UUID. Default: read from
                    linear-config.yml's linear.team.id.
  --scope SCOPE     Seed scope: `workspace` (workspace-wide labels,
                    requires workspace-admin) or `team` (labels scoped to
                    the team, requires only team-level permission).
                    Default: linear.seed.scope from config, else `team`.
  --dry-run         Log every mutation that WOULD fire; issue none. No
                    config.yml write.
  --workspace-only  Run the workspace mutations only — do NOT write the
                    captured UUIDs back to linear-config.yml. Useful when
                    verifying workspace state from a non-bridge-installed
                    context (e.g. dogfood from a sibling repo).
  --help            Show this help.

Exit codes:
  0  Success (possibly with warnings).
  1  Transient failure (5xx after retry, rate-limit exhaustion). Re-run.
  2  Workspace-level config error (missing config, malformed UUIDs, no
     team resolvable).
  3  Transport failure: Linear unreachable; nothing written.

See contracts/command-shapes.md §4 for the full contract.
EOF
}

# -----------------------------------------------------------------------------
# seed::log
#   Emit a per-mutation log line to stderr. Always on (the seed command is
#   short enough that --quiet is not worth a flag).
# -----------------------------------------------------------------------------
seed::log() {
    printf 'spec-kit-linear: seed %s\n' "$*" >&2
}

# -----------------------------------------------------------------------------
# seed::promote_exit <code>
#   Monotonically promote SEED_EXIT_CODE. Mirrors reconcile::promote_exit so
#   the operator-facing exit semantics are identical between the two entry
#   points. 2 is terminal (workspace-level halt) — never demote.
# -----------------------------------------------------------------------------
seed::promote_exit() {
    local incoming="$1"
    if (( SEED_EXIT_CODE == 2 )); then
        return 0
    fi
    case "$incoming" in
        2) SEED_EXIT_CODE=2 ;;
        3) (( SEED_EXIT_CODE < 3 )) && SEED_EXIT_CODE=3 ;;
        1) (( SEED_EXIT_CODE < 1 )) && SEED_EXIT_CODE=1 ;;
        0) : ;;
        *) : ;;
    esac
}

# =============================================================================
# Step 1 — Argument parsing.
# =============================================================================
seed::parse_args() {
    local config_path="${SEED_CONFIG_PATH_DEFAULT}"
    while (( $# > 0 )); do
        case "$1" in
            --team)
                if (( $# < 2 )); then
                    printf 'spec-kit-linear: --team requires a UUID argument\n' >&2
                    seed::usage
                    exit 2
                fi
                ARG_TEAM_OVERRIDE="$2"
                shift 2
                ;;
            --team=*)
                ARG_TEAM_OVERRIDE="${1#--team=}"
                shift
                ;;
            --dry-run)
                ARG_DRY_RUN=1
                shift
                ;;
            --workspace-only)
                ARG_WORKSPACE_ONLY=1
                shift
                ;;
            --scope)
                if (( $# < 2 )); then
                    printf 'spec-kit-linear: --scope requires an argument (workspace|team)\n' >&2
                    seed::usage
                    exit 2
                fi
                ARG_SEED_SCOPE="$2"
                shift 2
                ;;
            --scope=*)
                ARG_SEED_SCOPE="${1#--scope=}"
                shift
                ;;
            --config)
                if (( $# < 2 )); then
                    printf 'spec-kit-linear: --config requires a path argument\n' >&2
                    seed::usage
                    exit 2
                fi
                config_path="$2"
                shift 2
                ;;
            --config=*)
                config_path="${1#--config=}"
                shift
                ;;
            -h|--help)
                seed::usage
                exit 0
                ;;
            *)
                printf 'spec-kit-linear: unknown argument: %s\n' "$1" >&2
                seed::usage
                exit 2
                ;;
        esac
    done

    SEED_CONFIG_PATH="$config_path"
}

# =============================================================================
# Step 2 — Team UUID resolution.
#
# Order of precedence:
#   1. --team UUID on the CLI (operator override or non-interactive install).
#   2. linear.team.id parsed from .specify/extensions/linear/linear-config.yml.
#   3. Hard failure — without a team we cannot create team-scoped workflow
#      states. Exit 2 with an operator-actionable hint.
# =============================================================================
seed::resolve_team_uuid() {
    if [[ -n "$ARG_TEAM_OVERRIDE" ]]; then
        printf '%s\n' "$ARG_TEAM_OVERRIDE"
        return 0
    fi

    if [[ ! -e "$SEED_CONFIG_PATH" ]]; then
        summary::add error "no --team UUID supplied and ${SEED_CONFIG_PATH} not found"
        seed::promote_exit 2
        return 2
    fi

    # config::load + config::get_team_id will exit 2 if team.id is missing or
    # malformed. That matches the desired semantics (Principle VIII — surface,
    # don't enforce) so we let the propagation happen naturally.
    config::load "$SEED_CONFIG_PATH"
    config::get_team_id
}

# =============================================================================
# Step 2b — Seed scope resolution (spec 005, FR-005 / FR-006).
#
# Precedence:
#   1. --scope flag on the CLI (operator override / non-interactive
#      install).
#   2. linear.seed.scope from config (config::get_seed_scope), which itself
#      defaults to `team` when the block is absent (FR-013).
#   3. The hardcoded default `team`.
# An invalid --scope value halts (exit 2) with an actionable hint — we do
# NOT silently coerce (Principle VIII).
# =============================================================================
seed::resolve_scope() {
    if [[ -n "$ARG_SEED_SCOPE" ]]; then
        case "$ARG_SEED_SCOPE" in
            workspace|team)
                printf '%s\n' "$ARG_SEED_SCOPE"
                return 0
                ;;
            *)
                summary::add error "invalid --scope value '${ARG_SEED_SCOPE}' (valid: workspace, team)"
                seed::promote_exit 2
                return 2
                ;;
        esac
    fi

    # config may not be loaded (e.g. --team override with no config file);
    # fall back to the default in that case rather than halting.
    if [[ -n "${CONFIG_LOADED_PATH:-}" ]]; then
        config::get_seed_scope
        return 0
    fi
    printf 'team\n'
}

# =============================================================================
# Step 2c — Actionable permission/limit hint (spec 005, FR-004 / SC-003).
#
# seed::permission_hint <resource> <kind> [scope]
#   Surface a single, clear, actionable message when a create call fails
#   with a permission or limit error. It names the resource and the
#   failure kind, and points the operator at the adopt-existing path and
#   the team-scoped option — never a cryptic raw API error.
# =============================================================================
seed::permission_hint() {
    local resource="$1"
    local kind="$2"          # permission | limit
    local scope="${3:-$SEED_SCOPE}"

    local next
    if [[ "$scope" == "workspace" ]]; then
        next="re-run with --scope team (creates this resource scoped to your team, needing only team-level permission), or have an admin create it once — a later seed will ADOPT the existing resource without needing create permission."
    else
        next="have an admin (or a previous seed run) create this resource once — a later seed will ADOPT the existing resource by name without needing create permission."
    fi

    summary::add error \
        "create of '${resource}' failed (${kind} error in ${scope} scope). ${next}"
}

# =============================================================================
# Step 3 — Workflow-state idempotency probe + create (T058 + T060).
#
# Per contracts §2.1: before each workflowStateCreate, query
# `workflowStates(filter: { team: { id: { eq: $teamId } }, name: { eq: $name } })`.
# If exactly one match exists, capture its `id` and skip the mutation. If zero
# matches, call workflowStateCreate. >=2 matches surfaces a warning and skips
# (per the contract, "never auto-pick" on ambiguity).
# =============================================================================

# seed::query_workflow_state <team_uuid> <name>
#   Echo the matching workflowState UUID, or empty string on no match. Halts
#   the script (via graphql.sh) on auth / transport failure. Multi-match
#   surfaces a warning and echoes empty so the caller skips the create —
#   silent auto-pick is forbidden per the contract.
seed::query_workflow_state() {
    local team_uuid="$1"
    local name="$2"

    local query='query SeedFindWorkflowState($team: ID!, $name: String!) {
        workflowStates(
            filter: {
                team: { id:   { eq: $team } }
                name: { eq:   $name }
            }
        ) {
            nodes { id name type }
        }
    }'
    local vars
    vars="$(jq -nc \
        --arg team "$team_uuid" \
        --arg name "$name" \
        '{team: $team, name: $name}')"

    local response
    response="$(graphql::query "$query" "$vars")"

    local count
    count="$(printf '%s' "$response" | jq '.data.workflowStates.nodes | length')"
    case "$count" in
        0) printf '' ;;
        1) printf '%s' "$response" | jq -r '.data.workflowStates.nodes[0].id' ;;
        *)
            summary::add warned \
                "workflowStates query returned ${count} matches for name='${name}' on team ${team_uuid}; skipping create — operator must disambiguate manually"
            printf ''
            ;;
    esac
}

# Sentinel return code (spec 005): a create call was DENIED by a
# permission or limit error. Distinct from 0 (created) and 1 (fail-closed
# transport/graphql) so the caller can route to the adopt fallback
# (FR-006) rather than aborting (FR-014). 10 is well clear of the
# bridge's 0..3 exit-code space.
readonly SEED_RC_DENIED=10

# seed::create_workflow_state <team_uuid> <name> <type> <color> <position>
#   Issue a workflowStateCreate mutation and echo the resulting UUID.
#   Returns:
#     0               created; UUID on stdout
#     SEED_RC_DENIED  permission/limit error (caller falls back to adopt)
#     1               fail-closed (transport / graphql error)
#   On --dry-run, log + return a synthetic placeholder ID so the caller's
#   flow continues end-to-end (mirrors the reconcile.sh dry-run
#   convention).
seed::create_workflow_state() {
    local team_uuid="$1"
    local name="$2"
    local type="$3"
    local color="$4"
    local position="$5"

    if (( ARG_DRY_RUN == 1 )); then
        seed::log "DRY-RUN workflowStateCreate name='${name}' type=${type} color=${color} position=${position}"
        summary::add created "workflowStateCreate ${name} (dry-run)"
        # Synthesize a UUIDv4-shaped placeholder so the config-write path can
        # round-trip a dry-run end-to-end without choking on the regex check.
        printf '00000000-0000-0000-0000-dryrun%6s' "${name:0:6}" \
            | tr -c '0-9a-f-' '0' \
            | head -c 36
        printf '\n'
        return 0
    fi

    local mutation='mutation SeedWorkflowStateCreate($input: WorkflowStateCreateInput!) {
        workflowStateCreate(input: $input) {
            success
            workflowState { id name type }
        }
    }'
    local input_json vars
    input_json="$(jq -nc \
        --arg name "$name" \
        --arg type "$type" \
        --arg color "$color" \
        --arg team "$team_uuid" \
        --argjson position "$position" \
        '{
            name:     $name,
            type:     $type,
            color:    $color,
            teamId:   $team,
            position: $position
        }')"
    vars="$(jq -nc --argjson input "$input_json" '{input: $input}')"

    # Non-fatal capture so a permission/limit denial routes to adopt
    # rather than killing the run (FR-004 / FR-006).
    local envelope class
    envelope="$(graphql::mutate_capture "$mutation" "$vars")"
    class="$(printf '%s' "$envelope" | jq -r '.class // "transport"')"

    case "$class" in
        ok)
            local response
            response="$(printf '%s' "$envelope" | jq -c '.response')"
            if ! printf '%s' "$response" | jq -e '.data.workflowStateCreate.success == true' >/dev/null 2>&1; then
                summary::add error "workflowStateCreate ${name} did not return success=true"
                seed::promote_exit 1
                return 1
            fi
            summary::add created "workflowStateCreate ${name}"
            printf '%s\n' "$(printf '%s' "$response" | jq -r '.data.workflowStateCreate.workflowState.id')"
            return 0
            ;;
        permission|limit)
            seed::permission_hint "workflow state '${name}'" "$class"
            return "$SEED_RC_DENIED"
            ;;
        *)
            local msg
            msg="$(printf '%s' "$envelope" | jq -r '.message // "transport error"')"
            summary::add error "workflowStateCreate ${name} failed (${class}): ${msg}"
            seed::promote_exit 1
            return 1
            ;;
    esac
}

# seed::reconcile_workflow_states <team_uuid>
#   Drive T058 + T060: for each row in SEED_WORKFLOW_STATES, query → create
#   if absent → capture UUID into SEED_WORKFLOW_UUIDS keyed by lifecycle_key.
seed::reconcile_workflow_states() {
    local team_uuid="$1"
    local row key name type color position uuid rc
    for row in "${SEED_WORKFLOW_STATES[@]}"; do
        # Tab-separated parse — IFS scoped to the read so the surrounding
        # shell environment stays untouched.
        IFS=$'\t' read -r key name type color position <<<"$row"

        # The find-by-name probe runs first and is the basis of BOTH the
        # idempotent re-seed AND the adopt-existing path (FR-002, FR-003).
        # A multi-match returns empty (warn + skip per FR-010), so we never
        # capture an arbitrary UUID here.
        uuid="$(seed::query_workflow_state "$team_uuid" "$name")"
        if [[ -n "$uuid" ]]; then
            seed::log "workflow state '${name}' adopted (${uuid}); no create needed"
            summary::add skipped "workflow state '${name}' adopted (existing)"
            SEED_WORKFLOW_UUIDS[$key]="$uuid"
            continue
        fi

        rc=0
        uuid="$(seed::create_workflow_state "$team_uuid" "$name" "$type" "$color" "$position")" || rc=$?
        if (( rc == 0 )); then
            seed::log "created workflow state '${name}' → ${uuid}"
            SEED_WORKFLOW_UUIDS[$key]="$uuid"
            continue
        fi

        if (( rc == SEED_RC_DENIED )); then
            # Create not permitted — auto-fall-back to adopt (FR-006). The
            # probe above already came back empty, so the resource is
            # genuinely absent: it can be neither created nor adopted.
            # Record it for the could-not-provision listing (FR-011).
            SEED_UNRESOLVED["workflow state '${name}'"]=1
            seed::promote_exit 1
            continue
        fi

        # Fail-closed (transport/graphql) — create_workflow_state already
        # aggregated the error and promoted the exit code; move on.
    done
}

# =============================================================================
# Step 4 — Default-state capture (T059 secondary requirement).
#
# The team's stock workflow states (Todo / In Progress / Done) are queried via
# the same `workflowStates(filter: { team })` query, this time enumerating
# every state on the team and matching by (name, type) tuple. The bridge does
# NOT create these — Linear ships them on every team by default; if the
# operator has renamed or deleted them we surface a warning and skip the
# affected key rather than auto-recreating, because reconcile.sh treats
# default_state_uuids as optional-but-validated.
# =============================================================================

# seed::query_team_states <team_uuid>
#   Echo every workflow state on the team as JSON `[{id, name, type}, ...]`.
seed::query_team_states() {
    local team_uuid="$1"
    local query='query SeedListTeamStates($team: String!) {
        team(id: $team) {
            states { nodes { id name type } }
        }
    }'
    local vars
    vars="$(jq -nc --arg team "$team_uuid" '{team: $team}')"

    local response
    response="$(graphql::query "$query" "$vars")"
    printf '%s' "$response" | jq -c '.data.team.states.nodes'
}

# seed::capture_default_states <team_uuid>
#   Populate SEED_DEFAULT_STATE_UUIDS from the team's stock workflow states.
#   For each (key, expected_name, expected_type) row: prefer an exact name +
#   type match; fall back to the first state whose type matches alone.
seed::capture_default_states() {
    local team_uuid="$1"
    local team_states
    team_states="$(seed::query_team_states "$team_uuid")"

    local row key expected_name expected_type uuid
    for row in "${SEED_DEFAULT_STATE_LOOKUPS[@]}"; do
        IFS=$'\t' read -r key expected_name expected_type <<<"$row"

        # Exact (name, type) match first.
        uuid="$(printf '%s' "$team_states" | jq -r \
            --arg name "$expected_name" \
            --arg type "$expected_type" \
            '
            map(select(.name == $name and .type == $type))
            | (.[0].id // "")
            ')"

        # Fallback: first state with the expected type, regardless of name.
        if [[ -z "$uuid" ]]; then
            uuid="$(printf '%s' "$team_states" | jq -r \
                --arg type "$expected_type" \
                '
                map(select(.type == $type))
                | (.[0].id // "")
                ')"
            if [[ -n "$uuid" ]]; then
                # Operator has likely renamed Todo → Backlog or similar; the
                # bridge still works but we want the audit trail.
                local matched_name
                matched_name="$(printf '%s' "$team_states" | jq -r \
                    --arg id "$uuid" \
                    'map(select(.id == $id)) | (.[0].name // "")')"
                summary::add warned \
                    "default state '${key}': expected name='${expected_name}' type=${expected_type}; matched '${matched_name}' by type only"
            fi
        fi

        if [[ -z "$uuid" ]]; then
            # Default states are stock Linear team states that seed CAPTURES
            # but never creates — they are outside the create/adopt FR-011
            # provisioning loop. A missing one keeps its established
            # warn-only handling (pre-005 contract): surfaced, non-blocking.
            summary::add warned \
                "default state '${key}' (expected '${expected_name}', type ${expected_type}) not found on team ${team_uuid}; task-phase sub-issues will fail until this state exists"
            continue
        fi

        seed::log "default state '${key}' → ${uuid}"
        SEED_DEFAULT_STATE_UUIDS[$key]="$uuid"
    done
}

# =============================================================================
# Step 5 — Label idempotency probe + create (T059 + T060).
#
# Per contracts §2.2: pre-query each label by name; skip on hit. Labels are
# created as workspace-scoped (teamId omitted) so any team in the workspace
# can attach them — `phase:*` and `task-phase:*` are bridge-vocabulary that
# belongs to every consumer repo, not to a single team.
# =============================================================================

# seed::query_label <name>
#   Echo the matching label UUID or empty. Workspace-scoped labels live in
#   the same `issueLabels` collection as team-scoped ones; we filter by name
#   alone since the bridge owns the name family (`phase:*`, `task-phase:*`).
seed::query_label() {
    local name="$1"
    local query='query SeedFindLabel($name: String!) {
        issueLabels(filter: { name: { eq: $name } }) {
            nodes { id name }
        }
    }'
    local vars
    vars="$(jq -nc --arg name "$name" '{name: $name}')"

    local response
    response="$(graphql::query "$query" "$vars")"

    local count
    count="$(printf '%s' "$response" | jq '.data.issueLabels.nodes | length')"
    case "$count" in
        0) printf '' ;;
        1) printf '%s' "$response" | jq -r '.data.issueLabels.nodes[0].id' ;;
        *)
            summary::add warned \
                "issueLabels query returned ${count} matches for name='${name}'; skipping create — operator must disambiguate manually"
            printf ''
            ;;
    esac
}

# seed::create_label <name> [color] [scope] [team_uuid]
#   Issue an `issueLabelCreate` GraphQL mutation.
#     * scope=team (spec 005, FR-001) — pass `teamId` so the label is
#       created scoped to the team; needs only team-level permission so a
#       sub-team owner can seed without workspace-admin.
#     * scope=workspace (default, FR-013) — omit `teamId`; workspace-scoped
#       exactly as the pre-005 behaviour.
#   If <color> is omitted, Linear assigns a sensible default; pass a hex
#   color (e.g. `#14B8A6`) to lock the visual treatment for system label
#   families that need to be visually distinguishable (FR-036's agent:*).
#   Recolour in Linear's UI is non-fatal — lookups are by UUID (Principle V).
#   Returns:
#     0               created; UUID on stdout
#     SEED_RC_DENIED  permission/limit error (caller falls back to adopt)
#     1               fail-closed (transport / graphql error)
seed::create_label() {
    local name="$1"
    local color="${2:-}"
    local scope="${3:-$SEED_SCOPE}"
    local team_uuid="${4:-}"

    local scope_desc="workspace-scoped"
    if [[ "$scope" == "team" && -n "$team_uuid" ]]; then
        scope_desc="team-scoped (team ${team_uuid})"
    fi

    if (( ARG_DRY_RUN == 1 )); then
        if [[ -n "$color" ]]; then
            seed::log "DRY-RUN issueLabelCreate name='${name}' color='${color}' (${scope_desc})"
        else
            seed::log "DRY-RUN issueLabelCreate name='${name}' (${scope_desc})"
        fi
        summary::add created "issueLabelCreate ${name} (dry-run)"
        printf '00000000-0000-0000-0000-000000000000\n'
        return 0
    fi

    local mutation='mutation SeedLabelCreate($input: IssueLabelCreateInput!) {
        issueLabelCreate(input: $input) {
            success
            issueLabel { id name }
        }
    }'
    local input_json vars
    # Build the IssueLabelCreateInput, adding teamId only in team scope
    # (FR-001). Workspace scope omits it → workspace-scoped label (FR-013).
    input_json="$(jq -nc --arg name "$name" '{name: $name}')"
    if [[ -n "$color" ]]; then
        input_json="$(printf '%s' "$input_json" | jq -c --arg color "$color" '.color = $color')"
    fi
    if [[ "$scope" == "team" && -n "$team_uuid" ]]; then
        input_json="$(printf '%s' "$input_json" | jq -c --arg team "$team_uuid" '.teamId = $team')"
    fi
    vars="$(jq -nc --argjson input "$input_json" '{input: $input}')"

    local envelope class
    envelope="$(graphql::mutate_capture "$mutation" "$vars")"
    class="$(printf '%s' "$envelope" | jq -r '.class // "transport"')"

    case "$class" in
        ok)
            local response
            response="$(printf '%s' "$envelope" | jq -c '.response')"
            if ! printf '%s' "$response" | jq -e '.data.issueLabelCreate.success == true' >/dev/null 2>&1; then
                summary::add error "issueLabelCreate ${name} did not return success=true"
                seed::promote_exit 1
                return 1
            fi
            summary::add created "issueLabelCreate ${name} (${scope_desc})"
            printf '%s\n' "$(printf '%s' "$response" | jq -r '.data.issueLabelCreate.issueLabel.id')"
            return 0
            ;;
        permission|limit)
            seed::permission_hint "label '${name}'" "$class" "$scope"
            return "$SEED_RC_DENIED"
            ;;
        *)
            local msg
            msg="$(printf '%s' "$envelope" | jq -r '.message // "transport error"')"
            summary::add error "issueLabelCreate ${name} failed (${class}): ${msg}"
            seed::promote_exit 1
            return 1
            ;;
    esac
}

# seed::reconcile_labels
#   Walk both label families (phase:* and task-phase:N) and find-or-create
#   each. Captured UUIDs go into SEED_LABEL_UUIDS for diagnostics. Unlike the
#   workflow-state UUIDs these are NOT written to linear-config.yml — label
#   lookups inside reconcile.sh are by name (workspace-scoped, stable).
#   <team_uuid> is forwarded to create_label so team scope (FR-001) can
#   attach teamId. The phase / task-phase label UUIDs are diagnostics-only
#   (reconcile looks them up by name), so a denied-and-unadoptable label in
#   this family is NOT a could-not-provision blocker — but it IS reported.
seed::reconcile_labels() {
    local team_uuid="${1:-}"
    local name uuid rc
    local -a all_labels=()
    all_labels+=("${SEED_PHASE_LABELS[@]}")
    all_labels+=("${SEED_TASK_PHASE_LABELS[@]}")

    for name in "${all_labels[@]}"; do
        uuid="$(seed::query_label "$name")"
        if [[ -n "$uuid" ]]; then
            seed::log "label '${name}' adopted (${uuid}); no create needed"
            summary::add skipped "label '${name}' adopted (existing)"
            # shellcheck disable=SC2034  # diagnostics-only buffer
            SEED_LABEL_UUIDS[$name]="$uuid"
            continue
        fi

        rc=0
        uuid="$(seed::create_label "$name" "" "$SEED_SCOPE" "$team_uuid")" || rc=$?
        if (( rc == 0 )); then
            seed::log "created label '${name}' → ${uuid}"
            # shellcheck disable=SC2034  # diagnostics-only buffer
            SEED_LABEL_UUIDS[$name]="$uuid"
            continue
        fi
        if (( rc == SEED_RC_DENIED )); then
            # Create denied and the probe found nothing to adopt. These
            # labels are looked up by name (not persisted to config), so we
            # surface a warning but do not block the run on them.
            summary::add warned "label '${name}' could not be created (denied) and does not yet exist to adopt"
            seed::promote_exit 1
            continue
        fi
        # fail-closed already aggregated by create_label.
    done
}

# seed::reconcile_agent_labels
#   FR-036: find-or-create the `agent:claude` / `agent:codex` workspace
#   labels and capture their UUIDs into SEED_AGENT_LABEL_UUIDS keyed by
#   family name. Unlike the phase / task-phase families, these UUIDs ARE
#   written back to linear-config.yml (linear.agent_label_uuids) so
#   reconcile.sh can resolve them by family without a per-Issue name
#   lookup. A teal color is forced on create so the family is visually
#   distinct in Linear's UI; existing labels' colors are left untouched.
seed::reconcile_agent_labels() {
    local team_uuid="${1:-}"
    local row family name uuid rc
    for row in "${SEED_AGENT_LABELS[@]}"; do
        IFS=$'\t' read -r family name <<<"$row"

        uuid="$(seed::query_label "$name")"
        if [[ -n "$uuid" ]]; then
            seed::log "agent label '${name}' adopted (${uuid}); no create needed"
            summary::add skipped "label '${name}' adopted (existing)"
            # shellcheck disable=SC2034  # diagnostics-only buffer
            SEED_LABEL_UUIDS[$name]="$uuid"
            SEED_AGENT_LABEL_UUIDS[$family]="$uuid"
            continue
        fi

        rc=0
        uuid="$(seed::create_label "$name" "$SEED_AGENT_LABEL_COLOR" "$SEED_SCOPE" "$team_uuid")" || rc=$?
        if (( rc == 0 )); then
            seed::log "created agent label '${name}' → ${uuid}"
            # shellcheck disable=SC2034  # diagnostics-only buffer
            SEED_LABEL_UUIDS[$name]="$uuid"
            SEED_AGENT_LABEL_UUIDS[$family]="$uuid"
            continue
        fi
        if (( rc == SEED_RC_DENIED )); then
            # Agent-label UUIDs ARE persisted to config, so a denied +
            # unadoptable agent label is a could-not-provision blocker
            # (FR-011) — reconcile depends on it for the agent:* stamp.
            SEED_UNRESOLVED["agent label '${name}'"]=1
            seed::promote_exit 1
            continue
        fi
        # fail-closed already aggregated by create_label.
    done
}

# =============================================================================
# Step 6 — Config write-back (T060 second half).
#
# Update `.specify/extensions/linear/linear-config.yml` in place. Two cases:
#   * File exists: edit in place, preserving every field we did NOT touch.
#     The strategy is a per-line awk script that rewrites the
#     `linear.workflow_state_uuids` and `linear.default_state_uuids` blocks
#     wholesale (so the per-key indentation and ordering stay stable across
#     re-runs) and emits every other line verbatim.
#   * File missing: copy `config-template.yml` into place first, then apply
#     the same edit. This is the "fresh consumer repo, never installed"
#     bootstrap path; downstream `speckit.linear.install` still fills in
#     team/project UUIDs separately.
#
# We deliberately do NOT use `yq` — keeping the dependency surface at
# {bash, curl, jq, git} is a load-bearing decision in plan.md §Technical
# Context.
# =============================================================================

# seed::find_template
#   Locate the config template. Search order:
#     1. .specify/extensions/linear/config-template.yml — the post-install
#        location (where `specify extension add linear` drops it).
#     2. config-template.yml at the repo root — the dogfood location (this
#        repo's own committed template).
#     3. <SCRIPT_DIR>/../config-template.yml — relative to seed.sh, useful
#        when the bridge has been vendored into another tool.
#   Echo the first hit, or empty on no match.
seed::find_template() {
    local candidates=(
        ".specify/extensions/linear/${SEED_TEMPLATE_BASENAME}"
        "${SEED_TEMPLATE_BASENAME}"
        "${SCRIPT_DIR}/../${SEED_TEMPLATE_BASENAME}"
    )
    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    printf ''
}

# seed::ensure_config
#   Make sure linear-config.yml exists at SEED_CONFIG_PATH. If absent, copy
#   from the template and surface a warning so the operator knows they need
#   to run /spec-kit-linear-install next to fill in team + project UUIDs.
seed::ensure_config() {
    if [[ -f "$SEED_CONFIG_PATH" ]]; then
        return 0
    fi

    local template
    template="$(seed::find_template)"
    if [[ -z "$template" ]]; then
        summary::add error "linear-config.yml not found at ${SEED_CONFIG_PATH} and no config-template.yml available; cannot write captured UUIDs"
        seed::promote_exit 2
        return 2
    fi

    # Ensure the parent directory exists before the copy.
    local parent_dir
    parent_dir="$(dirname "$SEED_CONFIG_PATH")"
    if [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir"
    fi

    cp "$template" "$SEED_CONFIG_PATH"
    summary::add warned \
        "${SEED_CONFIG_PATH} was missing; copied from ${template}. Run /spec-kit-linear-install to fill in linear.team.id and linear.project.id."
}

# seed::render_workflow_uuid_block <indent>
#   Echo the YAML lines for the `workflow_state_uuids:` block, including the
#   block opener itself, with <indent> spaces of leading indent on the opener
#   (children indent two spaces deeper).
seed::render_workflow_uuid_block() {
    local indent="$1"
    local child_indent
    child_indent="${indent}  "

    printf '%sworkflow_state_uuids:\n' "$indent"

    # Render keys in the canonical order from CONFIG_WORKFLOW_PHASES so the
    # diff between re-runs is stable.
    local key value
    for key in specifying clarifying planning tasking red_team implementing analyzing ready_to_merge merged; do
        value="${SEED_WORKFLOW_UUIDS[$key]:-00000000-0000-0000-0000-000000000000}"
        printf '%s%s: "%s"\n' "$child_indent" "$key" "$value"
    done
}

# seed::render_default_state_uuid_block <indent>
#   Echo the YAML lines for the `default_state_uuids:` block.
seed::render_default_state_uuid_block() {
    local indent="$1"
    local child_indent
    child_indent="${indent}  "

    printf '%sdefault_state_uuids:\n' "$indent"

    local key value
    # "done" is quoted to keep shellcheck SC1010 from misreading the literal
    # iteration value as the loop-terminator keyword.
    for key in todo in_progress "done"; do
        value="${SEED_DEFAULT_STATE_UUIDS[$key]:-00000000-0000-0000-0000-000000000000}"
        printf '%s%s: "%s"\n' "$child_indent" "$key" "$value"
    done
}

# seed::render_agent_label_uuid_block <indent>
#   Echo the YAML lines for the `agent_label_uuids:` block (FR-036). Keys
#   are the agent family names (`claude`, `codex`); values are the
#   workspace label UUIDs captured by seed::reconcile_agent_labels. The
#   block is always emitted with both keys so reconcile.sh's getter has a
#   stable lookup target — missing labels surface as the zero placeholder
#   UUID, which config::get_agent_label_uuid rejects with a remediation
#   pointer back to /spec-kit-linear-seed.
seed::render_agent_label_uuid_block() {
    local indent="$1"
    local child_indent
    child_indent="${indent}  "

    printf '%sagent_label_uuids:\n' "$indent"

    local key value
    for key in claude codex; do
        value="${SEED_AGENT_LABEL_UUIDS[$key]:-00000000-0000-0000-0000-000000000000}"
        printf '%s%s: "%s"\n' "$child_indent" "$key" "$value"
    done
}

# seed::write_config_uuids
#   Splice the captured UUIDs into linear-config.yml. Strategy: a pure-bash
#   line-by-line rewrite that emits every input line verbatim EXCEPT when it
#   encounters the `workflow_state_uuids:` or `default_state_uuids:` opener;
#   on those, it emits the freshly-rendered replacement block in place of the
#   opener and then discards every subsequent indented child line until the
#   block ends (next sibling or end-of-`linear:` block).
#
#   When a block is missing entirely from the file (e.g. an older config that
#   pre-dates `default_state_uuids`), the missing block is appended at the
#   end of the `linear:` section.
#
#   We deliberately avoid awk's `-v` here — BSD awk (the macOS default)
#   rejects newline-bearing values, which our multi-line UUID blocks would
#   need. Pure bash also keeps the splice trivially testable from bats.
seed::write_config_uuids() {
    if (( ARG_WORKSPACE_ONLY == 1 )); then
        seed::log "--workspace-only: skipping config write"
        return 0
    fi
    if (( ARG_DRY_RUN == 1 )); then
        seed::log "DRY-RUN: skipping config write (would update ${SEED_CONFIG_PATH})"
        return 0
    fi

    seed::ensure_config || return $?

    # Render the three replacement blocks at the canonical indent (2 spaces —
    # children of `linear:`, sibling of `team:` / `project:`).
    local wf_block default_block agent_block
    wf_block="$(seed::render_workflow_uuid_block "  ")"
    default_block="$(seed::render_default_state_uuid_block "  ")"
    agent_block="$(seed::render_agent_label_uuid_block "  ")"

    local tmp_out
    tmp_out="$(mktemp -t spec-kit-linear-seed.XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -f '${tmp_out}'" RETURN

    # Per-line state machine:
    #   state="normal"      — emit verbatim
    #   state="skip_wf"     — inside an old workflow_state_uuids block; drop
    #                         children, resume on first non-child line
    #   state="skip_default"— inside an old default_state_uuids block; ditto
    #   state="skip_agent"  — inside an old agent_label_uuids block; ditto
    #
    # in_linear tracks whether we're inside the top-level `linear:` block so
    # we know to append missing replacement blocks before the next top-level
    # key (or at EOF).
    local state="normal"
    local in_linear=0
    local wf_seen=0
    local default_seen=0
    local agent_seen=0
    local line

    # IFS= + read -r + the `|| [[ -n "$line" ]]` tail preserves the final
    # line even when the file lacks a trailing newline.
    #
    # The inner `while :` loop is a re-dispatch mechanism: most branches `break`
    # it to advance to the next input line, but the skip-exit branch `continue`s
    # it to RE-PROCESS the current line (without reading a new one) so that a
    # managed-block opener sitting immediately after another managed block's
    # children can still be claimed by the opener-detection branches. See the
    # skip-exit branch below for why (#33, #39, #40).
    while IFS= read -r line || [[ -n "$line" ]]; do
      while :; do
        # End-of-`linear:` block — first top-level (no-leading-whitespace)
        # key after we entered it. Flush any missing replacement blocks
        # before the new top-level key.
        if (( in_linear == 1 )) && [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*: ]]; then
            if (( wf_seen == 0 )); then
                printf '%s\n' "$wf_block" >>"$tmp_out"
                wf_seen=1
            fi
            if (( default_seen == 0 )); then
                printf '%s\n' "$default_block" >>"$tmp_out"
                default_seen=1
            fi
            if (( agent_seen == 0 )); then
                printf '%s\n' "$agent_block" >>"$tmp_out"
                agent_seen=1
            fi
            in_linear=0
            state="normal"
            printf '%s\n' "$line" >>"$tmp_out"
            break
        fi

        # Top-level `linear:` opener — record + emit.
        if [[ "$line" =~ ^linear:[[:space:]]*$ ]]; then
            in_linear=1
            state="normal"
            printf '%s\n' "$line" >>"$tmp_out"
            break
        fi

        # workflow_state_uuids opener — emit replacement on first encounter,
        # drop silently on any subsequent encounter (legacy configs may have
        # duplicate openers from earlier splicer-bug runs; treat them as
        # stale and merge into the single canonical block we already emitted).
        if [[ "$state" == "normal" ]] \
            && [[ "$line" =~ ^[[:space:]]+workflow_state_uuids:[[:space:]]*$ ]]; then
            if (( wf_seen == 0 )); then
                printf '%s\n' "$wf_block" >>"$tmp_out"
                wf_seen=1
            fi
            state="skip_wf"
            break
        fi

        # default_state_uuids opener — same once-only emission semantics.
        if [[ "$state" == "normal" ]] \
            && [[ "$line" =~ ^[[:space:]]+default_state_uuids:[[:space:]]*$ ]]; then
            if (( default_seen == 0 )); then
                printf '%s\n' "$default_block" >>"$tmp_out"
                default_seen=1
            fi
            state="skip_default"
            break
        fi

        # agent_label_uuids opener (FR-036) — same once-only emission semantics.
        if [[ "$state" == "normal" ]] \
            && [[ "$line" =~ ^[[:space:]]+agent_label_uuids:[[:space:]]*$ ]]; then
            if (( agent_seen == 0 )); then
                printf '%s\n' "$agent_block" >>"$tmp_out"
                agent_seen=1
            fi
            state="skip_agent"
            break
        fi

        # While skipping an old replacement block, drop deeply-indented
        # children (4+ spaces) and comments. Any line at 2-or-fewer spaces
        # of indent is a sibling key — exit skip mode. We then re-dispatch the
        # line from the top of the loop so the opener-detection branches above
        # get a chance to claim it. This matters because a managed-block opener
        # can sit immediately after another managed block's last child (in the
        # shipped template `default_state_uuids:` directly follows
        # `workflow_state_uuids`'s children, separated only by comments). If we
        # emitted such a sibling verbatim here, the stale (zeroed) opener would
        # be copied AND the dedicated seen-flag flush would re-append the real
        # block → a duplicate YAML key (#33, #39, #40). Re-dispatching lets the
        # seen-flag logic own ALL emission of the three managed blocks exactly
        # once, regardless of their position. The inner-loop `continue` below
        # re-runs the dispatch body without consuming a new input line.
        if [[ "$state" == "skip_wf" ]] || [[ "$state" == "skip_default" ]] \
            || [[ "$state" == "skip_agent" ]]; then
            if [[ "$line" =~ ^\ \ \ \ [^[:space:]] ]] \
                || [[ "$line" =~ ^[[:space:]]+# ]]; then
                # Indented child / nested comment — drop it; advance a line.
                break
            fi
            # Sibling or blank — leave skip mode and re-dispatch this line so
            # the opener / end-of-linear branches above can claim it. `continue`
            # re-runs the inner loop body for the SAME line (redispatch); no new
            # input line is read.
            state="normal"
            continue
        fi

        # Default: emit verbatim, then advance to the next input line.
        printf '%s\n' "$line" >>"$tmp_out"
        break
      done
    done <"$SEED_CONFIG_PATH"

    # File ended mid-`linear:` block — flush any missing replacement blocks
    # at the end so the resulting config is complete even when the operator
    # has truncated the file to bare essentials.
    if (( in_linear == 1 )); then
        if (( wf_seen == 0 )); then
            printf '%s\n' "$wf_block" >>"$tmp_out"
        fi
        if (( default_seen == 0 )); then
            printf '%s\n' "$default_block" >>"$tmp_out"
        fi
        if (( agent_seen == 0 )); then
            printf '%s\n' "$agent_block" >>"$tmp_out"
        fi
    fi

    # Atomic-ish replace. `mv` on the same filesystem is atomic; if the
    # operator is doing something exotic (NFS, etc.) the previous file
    # contents are still recoverable from the tempfile location until the
    # trap fires.
    mv "$tmp_out" "$SEED_CONFIG_PATH"
    seed::log "wrote ${SEED_CONFIG_PATH}"
}

# =============================================================================
# Step 6b — Could-not-provision listing (spec 005, FR-011).
#
# When required PERSISTED resources (workflow states, default states,
# agent labels) could be neither created (no permission) nor adopted (not
# present), emit a single clear, actionable message listing every such
# resource by name so an admin knows exactly what to provision once — not
# a cryptic failure. Promotes the exit code so callers/CI observe the gap.
# =============================================================================
seed::report_unresolved() {
    if (( ${#SEED_UNRESOLVED[@]} == 0 )); then
        return 0
    fi

    local names
    names="$(printf '%s; ' "${!SEED_UNRESOLVED[@]}")"
    names="${names%; }"
    summary::add error \
        "${#SEED_UNRESOLVED[@]} required resource(s) could be neither created (no permission) nor adopted (not present): ${names}. Have an admin create them once, or re-run with --scope team; a later seed will adopt them."
    seed::promote_exit 1
}

# =============================================================================
# Step 7 — Main orchestration.
# =============================================================================
main() {
    seed::parse_args "$@"

    summary::start "speckit.linear seed"

    local team_uuid
    if ! team_uuid="$(seed::resolve_team_uuid)"; then
        # resolve_team_uuid already aggregated the error via summary::add.
        summary::emit
        exit "$SEED_EXIT_CODE"
    fi
    seed::log "team UUID: ${team_uuid}"

    # Resolve the seed scope (spec 005, FR-005): --scope flag → config →
    # default `team`. In team scope labels are created scoped to the team so
    # a non-admin sub-team owner can seed (FR-001).
    if ! SEED_SCOPE="$(seed::resolve_scope)"; then
        summary::emit
        exit "$SEED_EXIT_CODE"
    fi
    seed::log "seed scope: ${SEED_SCOPE}"

    if (( ARG_DRY_RUN == 1 )); then
        seed::log "DRY-RUN MODE: no Linear mutations will be issued; no config write"
    fi
    if (( ARG_WORKSPACE_ONLY == 1 )); then
        seed::log "--workspace-only: linear-config.yml will NOT be written"
    fi

    # T058: workflow states (9). States always take a team; existing states
    # are ADOPTED by name (FR-002, FR-003); create-denied auto-falls-back
    # to adopt (FR-006).
    seed::reconcile_workflow_states "$team_uuid"

    # Default-state capture (FR-005 / contracts §4.3) — Todo / In Progress /
    # Done UUIDs into SEED_DEFAULT_STATE_UUIDS.
    seed::capture_default_states "$team_uuid"

    # T059: labels (9 phase:* + 9 task-phase:N = 18 total). Scope-aware:
    # team scope passes teamId (FR-001); workspace scope omits it (FR-013).
    # Existing labels are ADOPTED by name.
    seed::reconcile_labels "$team_uuid"

    # FR-036: agent provenance labels (agent:claude, agent:codex). Captured
    # UUIDs land in SEED_AGENT_LABEL_UUIDS and are written into
    # linear-config.yml.linear.agent_label_uuids by the splicer below so
    # reconcile.sh's _resolve_agent_label_id helper can map the running
    # agent's family name to its label UUID without a per-Issue name lookup.
    seed::reconcile_agent_labels "$team_uuid"

    # FR-011: if any PERSISTED resource could be neither created nor
    # adopted, surface a single clear listing so an admin knows exactly
    # what to provision once — never a cryptic failure.
    seed::report_unresolved

    # T060 (write-back half): splice captured UUIDs into linear-config.yml.
    seed::write_config_uuids

    summary::emit

    # If any summary error fired, ensure exit code reflects that.
    if summary::has_errors; then
        seed::promote_exit 1
    fi

    exit "$SEED_EXIT_CODE"
}

# Allow sourcing under bats / unit tests without invoking main().
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
