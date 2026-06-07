#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016
# ^^^ Every GraphQL query string in this file uses single quotes so
#     `$variable` tokens remain literal — those are GraphQL variable
#     references resolved server-side, NOT bash expansions. Suppressing
#     SC2016 file-wide mirrors the convention in src/status.sh and
#     src/reconcile.sh.
# =============================================================================
# src/pull.sh — cross-repo unified spec view (Layer D, READ-ONLY).
#
# Implements User Story 3 (P2 — "Cross-repo unified view"; T052) and the
# `speckit.linear.pull` slice of `contracts/command-shapes.md`. The
# partner to `src/status.sh`: where status is filesystem-anchored and
# drift-aware, pull is Linear-anchored and inventory-aware. Returns
# "every spec across every repo bound to the operator's workspace"
# sorted by Project (= consumer repo), lifecycle phase, last-touched.
#
# Talks to Linear ONLY via `graphql::query`. Zero `graphql::mutate`,
# zero `issueCreate` / `issueUpdate` / `commentCreate` / any other
# mutation. The read path is the entire surface area — even from an
# authoritative worktree this command MUST NOT write.
#
# Two scopes the operator selects:
#   --repo            (default) every spec Issue in the local repo's
#                     bound Project. Uses linear.project.id from
#                     linear-config.yml.
#   --workspace-wide  every spec Issue across every Project the
#                     operator's team owns. Uses linear.team.id from
#                     linear-config.yml. Useful from any directory,
#                     even one not bound to a Linear project.
#
# Per-spec filter:
#   --phase PHASE     restrict to the named lifecycle phase
#                     (e.g. `--phase implementing`). Honours the same
#                     phase identifiers config::get_workflow_state_uuid
#                     accepts.
#   --all-phases      (default) no phase filter.
#
# -----------------------------------------------------------------------------
# Constitutional alignment
# -----------------------------------------------------------------------------
# Principle I (filesystem-is-truth)   — read-only; surfaces Linear-side
#   inventory without ever mutating. Filesystem state is not queried
#   per-spec (the Issue is the witness; the spec dir may live in a
#   sibling repo we can't reach).
# Principle II (reconcile, never event-push) — every invocation issues
#   fresh queries; no diff cache, no sidecar.
# Principle III (layered idempotency) — read-only by definition.
# Principle IV (write-authority-follows-worktree) — irrelevant: no
#   write path. Runs from any worktree, any branch.
# Principle V (UUID-based binding) — every filter uses the team UUID
#   (workspace-wide) or project UUID (--repo) resolved from
#   linear-config.yml.
# Principle VIII (observable failure) — query failures are surfaced via
#   summary::add. Empty workspace produces an empty JSON array (and a
#   warned event), never a crash.
#
# -----------------------------------------------------------------------------
# CLI surface (per task brief T052)
# -----------------------------------------------------------------------------
#   speckit.linear.pull [--repo | --workspace-wide]
#                       [--phase PHASE | --all-phases]
#                       [--json | --human]
#                       [--no-color]
#
# Defaults: `--repo --all-phases --human`.
#
# Exit codes (matching status.sh):
#   0  success (possibly with non-fatal warnings)
#   1  partial failure: a sub-query failed but other rows surfaced
#   2  workspace-level config error (missing config, malformed UUIDs)
#   3  transport failure across the board (config OK, Linear unreachable)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Module sourcing — order matches src/status.sh so a single shellcheck
# pass behaves identically across both entrypoints.
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

readonly PULL_CONFIG_PATH_DEFAULT=".specify/extensions/linear/linear-config.yml"

# Memory-block fences — copied from status.sh / reconcile.sh so we can
# parse out the recorded branch / worktree pointers from spec Issue
# descriptions. Same constants, same contract.
readonly PULL_MEMORY_BEGIN="<!-- spec-kit-linear:memory:begin -->"
readonly PULL_MEMORY_END="<!-- spec-kit-linear:memory:end -->"

# Canonical lifecycle phases accepted by --phase. Mirrors
# CONFIG_WORKFLOW_PHASES in config.sh — duplicated here so --phase
# validation does not require a loaded config (config is loaded later
# in main() once flags are known to be sane).
readonly -a PULL_KNOWN_PHASES=(
    "specifying"
    "clarifying"
    "planning"
    "tasking"
    "red_team"
    "implementing"
    "analyzing"
    "ready_to_merge"
    "merged"
)

# -----------------------------------------------------------------------------
# CLI-flag globals — populated by pull::parse_args.
# -----------------------------------------------------------------------------
declare -g ARG_SCOPE="repo"          # repo|workspace-wide
declare -g ARG_PHASE=""              # phase identifier or empty for all
declare -g ARG_FORMAT="human"        # human|json
declare -g ARG_NO_COLOR=0            # 0|1 — force monochrome
declare -g PULL_CONFIG_PATH=""       # resolved after parse_args

# Aggregate exit-code tracker (monotonic promotion).
declare -g PULL_EXIT_CODE=0

# Workspace url_key (informational; populates the URL column when set).
# Resolved from CONFIG_VALUES[linear.workspace.url_key] after config load.
declare -g PULL_URL_KEY=""

# Accumulator: one JSON object per Linear spec Issue. Newline-delimited
# so we can stream it through `jq -sc` at the end.
declare -g PULL_JSON_ROWS=""

# -----------------------------------------------------------------------------
# pull::usage
# -----------------------------------------------------------------------------
pull::usage() {
    cat >&2 <<'EOF'
Usage: pull.sh [--repo | --workspace-wide]
               [--phase PHASE | --all-phases]
               [--json | --human]
               [--no-color] [--config PATH] [--help]

Cross-repo unified view of spec Issues in Linear — READ-ONLY. Never mutates.

Options:
  --repo            (default) Only Issues in the local repo's bound Project.
                    Requires linear.project.id in linear-config.yml.
  --workspace-wide  Every Issue across every Project owned by the operator's
                    team. Requires linear.team.id in linear-config.yml.
  --phase PHASE     Restrict to a single lifecycle phase
                    (specifying|clarifying|planning|tasking|red_team|
                     implementing|analyzing|ready_to_merge|merged).
  --all-phases      (default) No phase filter.
  --json            Emit a JSON array of per-Issue objects on stdout.
  --human           Emit a coloured table grouped by Project (default).
  --no-color        Force monochrome (also honoured via NO_COLOR).
  --config PATH     Override the path to linear-config.yml.
  --help            Show this help.

Exit codes:
  0  Success (possibly with warnings).
  1  Partial failure: at least one query failed.
  2  Workspace-level config error (halt without partial output).
  3  Transport failure: Linear unreachable.
EOF
}

# -----------------------------------------------------------------------------
# pull::log
# -----------------------------------------------------------------------------
pull::log() {
    printf 'spec-kit-linear: pull %s\n' "$*" >&2
}

# -----------------------------------------------------------------------------
# pull::promote_exit <code>
#   Monotonically promote PULL_EXIT_CODE. Mirrors status::promote_exit.
# -----------------------------------------------------------------------------
pull::promote_exit() {
    local incoming="$1"
    if (( PULL_EXIT_CODE == 2 )); then
        return 0
    fi
    case "$incoming" in
        2) PULL_EXIT_CODE=2 ;;
        3) (( PULL_EXIT_CODE < 3 )) && PULL_EXIT_CODE=3 ;;
        1) (( PULL_EXIT_CODE < 1 )) && PULL_EXIT_CODE=1 ;;
        0) : ;;
        *) : ;;
    esac
}

# =============================================================================
# Step 1 — Argument parsing.
# =============================================================================
pull::parse_args() {
    local config_path="${PULL_CONFIG_PATH_DEFAULT}"
    while (( $# > 0 )); do
        case "$1" in
            --repo)
                ARG_SCOPE="repo"
                shift
                ;;
            --workspace-wide)
                ARG_SCOPE="workspace-wide"
                shift
                ;;
            --phase)
                if (( $# < 2 )); then
                    printf 'spec-kit-linear: --phase requires a phase identifier\n' >&2
                    pull::usage
                    exit 2
                fi
                ARG_PHASE="$2"
                shift 2
                ;;
            --phase=*)
                ARG_PHASE="${1#--phase=}"
                shift
                ;;
            --all-phases)
                # No-op default surface: empty ARG_PHASE already means
                # "all phases". We accept the flag for operator clarity
                # and so a later --phase X --all-phases pair resets the
                # filter in the expected left-to-right order.
                ARG_PHASE=""
                shift
                ;;
            --json)
                ARG_FORMAT="json"
                shift
                ;;
            --human)
                ARG_FORMAT="human"
                shift
                ;;
            --no-color|--no-colour)
                ARG_NO_COLOR=1
                shift
                ;;
            --config)
                if (( $# < 2 )); then
                    printf 'spec-kit-linear: --config requires a path argument\n' >&2
                    pull::usage
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
                pull::usage
                exit 0
                ;;
            *)
                printf 'spec-kit-linear: unknown argument: %s\n' "$1" >&2
                pull::usage
                exit 2
                ;;
        esac
    done

    # Honour the NO_COLOR convention.
    if (( ARG_NO_COLOR == 1 )); then
        export NO_COLOR=1
    fi

    # Validate --phase against the canonical list. Empty phase = all
    # phases (the default); unknown phase = exit 2 (operator typo).
    if [[ -n "$ARG_PHASE" ]]; then
        local known=0 candidate
        for candidate in "${PULL_KNOWN_PHASES[@]}"; do
            if [[ "$candidate" == "$ARG_PHASE" ]]; then
                known=1
                break
            fi
        done
        if (( known == 0 )); then
            printf 'spec-kit-linear: unknown --phase: %s\n' "$ARG_PHASE" >&2
            printf 'hint: valid phases are %s\n' "${PULL_KNOWN_PHASES[*]}" >&2
            exit 2
        fi
    fi

    # Materialise the resolved config path for downstream readers.
    PULL_CONFIG_PATH="$config_path"
    if [[ -n "${SPECKIT_LINEAR_CONFIG:-}" ]]; then
        PULL_CONFIG_PATH="${SPECKIT_LINEAR_CONFIG}"
    fi
}

# =============================================================================
# Step 2 — Linear-side query construction & execution.
#
# Strategy: one GraphQL query per invocation. The filter is the only
# thing that changes between --repo and --workspace-wide:
#
#   --repo:           project.id eq <project_uuid> AND
#                     labels.name startsWith "speckit-spec:"
#   --workspace-wide: team.id    eq <team_uuid>    AND
#                     labels.name startsWith "speckit-spec:"
#
# `--phase X` adds a top-level `and` clause restricting labels.name to
# the exact `phase:X` value. Linear's IssueFilter supports a top-level
# `and: [IssueFilter!]` so we can compose label-name conditions without
# fighting the AND-within-single-field semantics.
# =============================================================================

# pull::build_filter_json
#   Echo the JSON literal that becomes the `filter` argument of the
#   issues() query. The caller passes it as a variable so the query
#   string stays single-quoted and shellcheck-clean.
pull::build_filter_json() {
    local team_uuid="$1"
    local project_uuid="$2"
    local scope="$3"
    local phase="$4"

    # Base "is a spec Issue" clause: label whose name starts with
    # "speckit-spec:". We use startsWith so we don't have to enumerate
    # every NNN value.
    local base
    base="$(jq -nc \
        --arg prefix "speckit-spec:" \
        '{labels: {name: {startsWith: $prefix}}}')"

    # Scope clause: project (repo scope) or team (workspace-wide).
    local scope_clause
    case "$scope" in
        repo)
            scope_clause="$(jq -nc \
                --arg id "$project_uuid" \
                '{project: {id: {eq: $id}}}')"
            ;;
        workspace-wide)
            scope_clause="$(jq -nc \
                --arg id "$team_uuid" \
                '{team: {id: {eq: $id}}}')"
            ;;
        *)
            scope_clause='{}'
            ;;
    esac

    # Compose base AND scope. If --phase is set, AND that too via the
    # top-level `and` clause so we can match the second label-name
    # condition without conflicting with the speckit-spec:* prefix
    # filter (both target labels.name).
    if [[ -n "$phase" ]]; then
        local phase_clause
        phase_clause="$(jq -nc \
            --arg phase_label "phase:${phase}" \
            '{labels: {name: {eq: $phase_label}}}')"
        jq -nc \
            --argjson base "$base" \
            --argjson scope "$scope_clause" \
            --argjson phase_c "$phase_clause" \
            '$base + $scope + {and: [$phase_c]}'
    else
        jq -nc \
            --argjson base "$base" \
            --argjson scope "$scope_clause" \
            '$base + $scope'
    fi
}

# pull::query_spec_issues <filter_json>
#   Execute the spec-Issue query and echo the .data.issues.nodes array
#   as a JSON list. Returns non-zero on transport / GraphQL failure so
#   the caller can decide whether to promote the exit code.
pull::query_spec_issues() {
    local filter_json="$1"

    # The query asks for every field the human / JSON renderer needs.
    # `project { id name }` powers the per-Project grouping.
    # `assignee { id name }` covers FR-034.
    # `estimate` covers the FR-035 rollup.
    # `team { key organization { urlKey } }` gives a URL fallback when
    # linear.workspace.url_key isn't set locally.
    local query='query PullSpecIssues($filter: IssueFilter!) {
        issues(filter: $filter, first: 250) {
            nodes {
                id
                identifier
                title
                updatedAt
                description
                estimate
                state { id name type }
                labels { nodes { name } }
                project { id name }
                assignee { id name displayName }
                team { id key organization { urlKey } }
            }
        }
    }'

    local vars
    vars="$(jq -nc --argjson f "$filter_json" '{filter: $f}')"

    local response
    if ! response="$(graphql::query "$query" "$vars" 2>/dev/null)"; then
        return 1
    fi

    printf '%s' "$response" | jq -c '.data.issues.nodes // []'
}

# =============================================================================
# Step 3 — Per-Issue row assembly.
# =============================================================================

# pull::extract_memory_field <description> <label>
#   Walk the memory block fenced by PULL_MEMORY_BEGIN..PULL_MEMORY_END
#   and echo the value cell for the first row whose first cell is
#   "**<label>**". Used to surface branch / worktree the spec Issue
#   last recorded. Empty if absent.
pull::extract_memory_field() {
    local description="$1"
    local label="$2"
    if [[ -z "$description" ]]; then
        return 0
    fi
    awk -v begin="$PULL_MEMORY_BEGIN" \
        -v end="$PULL_MEMORY_END" \
        -v want="**${label}**" '
        index($0, begin) { in_block = 1; next }
        index($0, end)   { in_block = 0; next }
        in_block {
            n = split($0, cells, "|")
            if (n >= 4) {
                key = cells[2]
                val = cells[3]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
                if (key == want) {
                    gsub(/^`|`$/, "", val)
                    print val
                    exit
                }
            }
        }
    ' <<<"$description"
}

# pull::feature_number_from_labels <labels_json_nodes>
#   Echo the first NNN extracted from any `speckit-spec:NNN` label, or
#   empty if none found.
pull::feature_number_from_labels() {
    local labels_json="$1"
    if [[ -z "$labels_json" || "$labels_json" == "null" ]]; then
        return 0
    fi
    printf '%s' "$labels_json" | jq -r '
        [.[] | .name | select(startswith("speckit-spec:")) | sub("^speckit-spec:"; "")]
        | (first // "")
    '
}

# pull::phase_label_from_labels <labels_json_nodes>
#   Echo the `phase:*` label's suffix (the lifecycle phase identifier),
#   or empty if no phase label is attached.
pull::phase_label_from_labels() {
    local labels_json="$1"
    if [[ -z "$labels_json" || "$labels_json" == "null" ]]; then
        return 0
    fi
    printf '%s' "$labels_json" | jq -r '
        [.[] | .name | select(startswith("phase:")) | sub("^phase:"; "")]
        | (first // "")
    '
}

# pull::build_issue_url <identifier> <team_url_key_fallback>
#   Compose the Linear issue URL. Prefers the workspace url_key from
#   linear-config.yml; falls back to the per-Issue team's organization
#   urlKey returned by the query. Empty when neither is available
#   (rare — Linear always knows its own urlKey).
pull::build_issue_url() {
    local identifier="$1"
    local fallback_url_key="$2"
    local key="${PULL_URL_KEY:-$fallback_url_key}"
    if [[ -z "$key" || -z "$identifier" ]]; then
        return 0
    fi
    printf 'https://linear.app/%s/issue/%s' "$key" "$identifier"
}

# pull::process_issue <issue_json>
#   Build one row of output from a single Linear Issue node. Appends a
#   compact JSON object to PULL_JSON_ROWS. Renderers consume the array
#   downstream.
pull::process_issue() {
    local issue_json="$1"

    local identifier title updated_at description estimate
    local state_name state_type
    local project_id project_name assignee_name
    local team_url_key
    identifier="$(printf '%s' "$issue_json" | jq -r '.identifier // ""')"
    title="$(printf '%s' "$issue_json" | jq -r '.title // ""')"
    updated_at="$(printf '%s' "$issue_json" | jq -r '.updatedAt // ""')"
    description="$(printf '%s' "$issue_json" | jq -r '.description // ""')"
    # `.estimate` is numeric or null; preserve null as empty string in
    # the human view, surface the number itself in JSON.
    estimate="$(printf '%s' "$issue_json" | jq -r '.estimate // ""')"
    state_name="$(printf '%s' "$issue_json" | jq -r '.state.name // ""')"
    state_type="$(printf '%s' "$issue_json" | jq -r '.state.type // ""')"
    project_id="$(printf '%s' "$issue_json" | jq -r '.project.id // ""')"
    project_name="$(printf '%s' "$issue_json" | jq -r '.project.name // "<no project>"')"
    # Prefer `displayName` (Linear's user-facing handle); fall back to
    # the plain `name`. Empty stays empty so the renderer can show "—".
    assignee_name="$(printf '%s' "$issue_json" \
        | jq -r '(.assignee.displayName // .assignee.name // "")')"
    team_url_key="$(printf '%s' "$issue_json" | jq -r '.team.organization.urlKey // ""')"

    local labels_json
    labels_json="$(printf '%s' "$issue_json" | jq -c '.labels.nodes // []')"

    local feature_number phase_label
    feature_number="$(pull::feature_number_from_labels "$labels_json")"
    phase_label="$(pull::phase_label_from_labels "$labels_json")"

    local memory_branch memory_worktree
    memory_branch="$(pull::extract_memory_field "$description" "Branch")"
    memory_worktree="$(pull::extract_memory_field "$description" "Worktree")"

    local url
    url="$(pull::build_issue_url "$identifier" "$team_url_key")"

    # Emit `estimate` as a JSON number when present, else null. Same
    # for the boolean-ish "assignee present" gate.
    local estimate_json="null"
    if [[ -n "$estimate" && "$estimate" != "null" ]]; then
        # Numeric-looking estimates only; defensive against future
        # Linear schema drift.
        if [[ "$estimate" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
            estimate_json="$estimate"
        fi
    fi

    local row_json
    row_json="$(jq -nc \
        --arg identifier "$identifier" \
        --arg feature_number "$feature_number" \
        --arg title "$title" \
        --arg project_id "$project_id" \
        --arg project_name "$project_name" \
        --arg state_name "$state_name" \
        --arg state_type "$state_type" \
        --arg phase_label "$phase_label" \
        --arg branch "$memory_branch" \
        --arg worktree "$memory_worktree" \
        --arg last_activity "$updated_at" \
        --arg assignee_name "$assignee_name" \
        --argjson estimate "$estimate_json" \
        --arg url "$url" \
        '{
            identifier: $identifier,
            feature_number: $feature_number,
            title: $title,
            project_id: $project_id,
            project_name: $project_name,
            state_name: $state_name,
            state_type: $state_type,
            phase_label: $phase_label,
            branch: $branch,
            worktree: $worktree,
            last_activity: $last_activity,
            assignee_name: $assignee_name,
            estimate: $estimate,
            url: $url
        }')"

    if [[ -z "$PULL_JSON_ROWS" ]]; then
        PULL_JSON_ROWS="$row_json"
    else
        PULL_JSON_ROWS="${PULL_JSON_ROWS}"$'\n'"${row_json}"
    fi
}

# =============================================================================
# Step 4 — Output rendering.
# =============================================================================

# pull::collected_rows_json
#   Echo the captured rows as a single JSON array, sorted by Project,
#   lifecycle phase, then last_activity descending (most-recent first
#   within a phase). Used by both human and JSON renderers.
pull::collected_rows_json() {
    if [[ -z "$PULL_JSON_ROWS" ]]; then
        printf '[]'
        return 0
    fi
    # Define a phase ordering JSON map inline so jq can sort by it.
    # Unknown / empty phases sort last (sentinel 99).
    printf '%s\n' "$PULL_JSON_ROWS" | jq -sc '
        def phase_rank(p):
            { "specifying": 0, "clarifying": 1, "planning": 2,
              "tasking": 3, "red_team": 4, "implementing": 5,
              "analyzing": 6, "ready_to_merge": 7, "merged": 8 }
            | (.[p] // 99);
        sort_by([
            (.project_name // ""),
            phase_rank(.phase_label // ""),
            -( (.last_activity // "") | (try fromdateiso8601 catch 0) )
        ])
    '
}

# pull::emit_json
pull::emit_json() {
    pull::collected_rows_json
    printf '\n'
}

# pull::_supports_color
#   Mirror status::_supports_color — human table goes to stdout.
pull::_supports_color() {
    if (( ARG_NO_COLOR == 1 )); then
        return 1
    fi
    if [[ -n "${NO_COLOR:-}" ]]; then
        return 1
    fi
    if [[ -t 1 ]]; then
        return 0
    fi
    return 1
}

# pull::_colour <code> <text>
pull::_colour() {
    local code="$1"
    local text="$2"
    if pull::_supports_color; then
        printf '\033[%sm%s\033[0m' "$code" "$text"
    else
        printf '%s' "$text"
    fi
}

# pull::emit_human
#   Render a Project-grouped scannable table on stdout. Each Project
#   gets a bold header line; rows under it are tab-aligned via column.
pull::emit_human() {
    local rows_json
    rows_json="$(pull::collected_rows_json)"

    local row_count
    row_count="$(printf '%s' "$rows_json" | jq 'length')"
    if (( row_count == 0 )); then
        printf 'speckit.linear.pull: no spec Issues found\n'
        if [[ -n "$ARG_PHASE" ]]; then
            printf '  (filter: --phase %s)\n' "$ARG_PHASE"
        fi
        if [[ "$ARG_SCOPE" == "repo" ]]; then
            printf '  (scope: --repo — only Issues in the bound Project)\n'
        else
            printf '  (scope: --workspace-wide — all Projects in the team)\n'
        fi
        return 0
    fi

    # Distinct Project names, in the same order rows already appear
    # (the sort was project_name ascending).
    local -a project_names=()
    local pn
    while IFS= read -r pn; do
        [[ -z "$pn" ]] && continue
        project_names+=("$pn")
    done < <(printf '%s' "$rows_json" \
        | jq -r '[.[].project_name] | unique | .[]')

    local header
    printf -v header 'ID\tNNN\tPHASE\tSTATE\tEST\tASSIGNEE\tLAST ACTIVITY\tTITLE'

    local project
    for project in "${project_names[@]}"; do
        # Project header — coloured bold cyan when stdout is a tty.
        local project_header
        project_header="$(pull::_colour '1;36' "▼ ${project}")"
        printf '\n%s\n' "$project_header"

        local rows_for_project
        rows_for_project="$(printf '%s' "$rows_json" \
            | jq -r --arg p "$project" '
                .[] | select(.project_name == $p)
                | [
                    .identifier,
                    .feature_number,
                    (.phase_label // ""),
                    (.state_name // ""),
                    (if (.estimate == null) then "" else (.estimate | tostring) end),
                    (.assignee_name // ""),
                    (.last_activity // ""),
                    (.title // "")
                  ]
                | @tsv
            ')"

        # Colourise the PHASE cell per the lifecycle ordering — early
        # phases yellow (planning/specifying), mid blue (implementing),
        # late green (merged/ready_to_merge), unknown grey.
        local coloured_rows=""
        local row
        local col_id col_nnn col_phase col_state col_est col_assignee col_last col_title
        while IFS= read -r row; do
            [[ -z "$row" ]] && continue
            # `@tsv` emits real tabs ONLY between fields (tabs inside a field are
            # escaped to \t), so swap them for a non-whitespace unit separator
            # before splitting. `IFS=$'\t' read` collapses empty fields because
            # tab is IFS-WHITESPACE — an empty PHASE/EST cell would swallow a tab
            # and shift every later column left (the alignment bug). US (0x1f) is
            # non-whitespace, so `read` preserves empty fields.
            local row_us="${row//$'\t'/$'\037'}"
            IFS=$'\037' read -r col_id col_nnn col_phase col_state col_est col_assignee col_last col_title <<<"$row_us"
            local phase_coloured
            case "$col_phase" in
                specifying|clarifying|planning|tasking|red_team)
                    phase_coloured="$(pull::_colour 33 "${col_phase:-—}")"
                    ;;
                implementing|analyzing)
                    phase_coloured="$(pull::_colour 34 "${col_phase:-—}")"
                    ;;
                ready_to_merge|merged)
                    phase_coloured="$(pull::_colour 32 "${col_phase:-—}")"
                    ;;
                "")
                    phase_coloured="$(pull::_colour 90 "—")"
                    ;;
                *)
                    phase_coloured="$col_phase"
                    ;;
            esac
            local cr
            printf -v cr '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
                "${col_id:-—}" \
                "${col_nnn:-—}" \
                "$phase_coloured" \
                "${col_state:-—}" \
                "${col_est:-—}" \
                "${col_assignee:-—}" \
                "${col_last:-—}" \
                "${col_title:-—}"
            if [[ -z "$coloured_rows" ]]; then
                coloured_rows="$cr"
            else
                coloured_rows="${coloured_rows}"$'\n'"${cr}"
            fi
        done <<<"$rows_for_project"

        {
            printf '%s\n' "$header"
            printf '%s\n' "$coloured_rows"
        } | (column -t -s $'\t' 2>/dev/null || cat)
    done
}

# =============================================================================
# Step 5 — Entry point.
# =============================================================================
main() {
    pull::parse_args "$@"

    summary::start "speckit.linear pull (--${ARG_SCOPE}${ARG_PHASE:+ --phase ${ARG_PHASE}})"

    # Config load + validate. Halts (exit 2) on missing / malformed
    # config per FR-022. --workspace-wide still requires a config —
    # team_id is the lookup key — but does NOT require project.id to
    # be set to a real Project (the workspace scope sidesteps it).
    if ! config::load "$PULL_CONFIG_PATH"; then
        printf 'spec-kit-linear: pull: cannot load config at %s\n' "$PULL_CONFIG_PATH" >&2
        printf 'hint: copy config-template.yml to %s and run /spec-kit-linear-install\n' \
            "$PULL_CONFIG_PATH" >&2
        summary::add error "config load failed: ${PULL_CONFIG_PATH}"
        summary::emit
        exit 2
    fi
    if ! config::validate; then
        printf 'spec-kit-linear: pull: config validation failed at %s\n' "$PULL_CONFIG_PATH" >&2
        summary::add error "config validation failed"
        summary::emit
        exit 2
    fi

    # Cache the workspace url_key (informational) for URL composition.
    # CONFIG_VALUES is populated by config::load.
    PULL_URL_KEY="${CONFIG_VALUES[linear.workspace.url_key]:-}"

    # Resolve UUIDs for the chosen scope. We tolerate missing
    # project.id when --workspace-wide is in effect (the team UUID is
    # the only lookup key needed).
    local team_uuid="" project_uuid=""
    team_uuid="$(config::get_team_id 2>/dev/null || printf '')"
    if [[ "$ARG_SCOPE" == "repo" ]]; then
        if ! project_uuid="$(config::get_project_id 2>/dev/null)"; then
            project_uuid=""
        fi
        if [[ -z "$project_uuid" ]]; then
            printf 'spec-kit-linear: pull: --repo requires linear.project.id in %s\n' \
                "$PULL_CONFIG_PATH" >&2
            printf 'hint: run /spec-kit-linear-install to bind a Project, or use --workspace-wide\n' >&2
            summary::add error "linear.project.id missing for --repo scope"
            summary::emit
            exit 2
        fi
    else
        if [[ -z "$team_uuid" ]]; then
            printf 'spec-kit-linear: pull: --workspace-wide requires linear.team.id in %s\n' \
                "$PULL_CONFIG_PATH" >&2
            summary::add error "linear.team.id missing for --workspace-wide scope"
            summary::emit
            exit 2
        fi
    fi

    pull::log "scope=${ARG_SCOPE} phase=${ARG_PHASE:-<all>} format=${ARG_FORMAT}"

    # Build the filter & execute the single spec-Issue query.
    local filter_json
    filter_json="$(pull::build_filter_json \
        "$team_uuid" "$project_uuid" "$ARG_SCOPE" "$ARG_PHASE")"

    local nodes_json
    if ! nodes_json="$(pull::query_spec_issues "$filter_json")"; then
        summary::add error "Linear query failed; no rows surfaced"
        pull::promote_exit 3
        nodes_json="[]"
    fi

    local node_count
    node_count="$(printf '%s' "$nodes_json" | jq 'length')"

    if (( node_count == 0 )); then
        summary::add warned "no spec Issues matched the requested filter"
    fi

    # Walk every node and accumulate a row.
    local i
    for (( i = 0; i < node_count; i++ )); do
        local issue_json
        issue_json="$(printf '%s' "$nodes_json" | jq -c ".[$i]")"
        pull::process_issue "$issue_json"
    done

    # Emit the report to stdout (JSON or human). The structured summary
    # goes to stderr per Principle VIII.
    case "$ARG_FORMAT" in
        json)  pull::emit_json ;;
        human) pull::emit_human ;;
    esac

    summary::emit
    if summary::has_errors; then
        pull::promote_exit 1
    fi
    exit "$PULL_EXIT_CODE"
}

# Allow sourcing under bats / unit tests without invoking main().
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
