#!/usr/bin/env bash
# shellcheck shell=bash
#
# src/config.sh — loader + validator for
# `.specify/extensions/linear/linear-config.yml`.
#
# Sourced by other bridge scripts. Never executed directly. Public API
# uses the `config::*` namespace per the project convention.
#
# Per Principle V (UUID-based binding) every Linear identifier the
# bridge consumes is a UUID stored in the per-repo config. This module
# enforces that contract on every invocation BEFORE any downstream
# code is allowed to talk to Linear (FR-022, Principle VIII Rule 1).
#
# Behaviour summary:
#   config::load <path>                      — parse + populate state
#   config::get_team_id                      — echo team UUID
#   config::get_project_id                   — echo project UUID
#   config::get_workflow_state_uuid <phase>  — echo UUID for one of the
#       nine lifecycle phases (specifying|clarifying|planning|tasking|
#       red_team|implementing|analyzing|ready_to_merge|merged)
#   config::get_default_state_uuid <key>     — echo UUID for a stock
#       team state used by task-phase sub-issues (todo|in_progress|done).
#       The `default_state_uuids` block is added during the post-analyze
#       remediation; absence is surfaced as an actionable error.
#   config::validate                         — confirm every required
#       UUID is present + well-formed; exit 2 with operator-actionable
#       diagnostics on failure (Principle VIII).
#
# YAML parsing strategy: the config file is shallow (one nesting level
# beneath top-level keys, plus the flat `workflow_state_uuids` and
# `default_state_uuids` maps), so we parse it with awk + sed rather than
# pulling in yq. yq is intentionally NOT a required dependency per
# `plan.md` §Technical Context — keeping the dep surface to bash + curl
# + jq + git lets the bridge install cleanly on a stock macOS / Ubuntu
# operator workstation.

set -euo pipefail

# ---------------------------------------------------------------------------
# Module-level state. All keys are flattened "dotted" paths (e.g.
# `linear.team.id`, `linear.workflow_state_uuids.specifying`). One
# associative array keeps the parser's output discoverable to every
# getter without re-reading the file.
# ---------------------------------------------------------------------------

declare -gA CONFIG_VALUES=()
declare -g CONFIG_LOADED_PATH=""

# ---------------------------------------------------------------------------
# Operator-local identity store (spec 004 — config / identity split).
# Identity (user_id, name, email) lives in a SEPARATE gitignored file,
# never in the committed `linear-config.yml`. The store is parsed into a
# second associative array so the committed-config getters and the
# identity getters never read from each other's namespace (FR-002,
# FR-005). Resolution for identity is env → this store → (caller prompt).
# ---------------------------------------------------------------------------
declare -gA CONFIG_OPERATOR_VALUES=()
# Diagnostic-only: records which operator-local file populated the store
# (empty when none was found). Parallels CONFIG_LOADED_PATH; surfaced by
# config::operator_loaded_path for callers/tests that want to assert the
# source.
declare -g CONFIG_OPERATOR_LOADED_PATH=""

# Default location of the operator-local identity file, resolved relative
# to PWD (the consumer repo root) like the committed config. The
# `*.local.yml` suffix is matched by a single `.gitignore` glob.
readonly CONFIG_OPERATOR_LOCAL_PATH_DEFAULT=".specify/extensions/linear/linear-operator.local.yml"

# One-shot latch so the legacy-config migration notice (FR-007) is
# emitted at most once per process. Idempotency across PROCESSES is
# guaranteed structurally: the migration removes the `operator:` block
# from the committed file, so the detector never fires on a later run.
declare -g _CONFIG_MIGRATION_NOTICE_EMITTED=0

# UUID regex per RFC 4122 (lowercase hex). Validation accepts upper or
# lower case but the canonical form the seed step emits is lowercase.
readonly CONFIG_UUID_REGEX='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

# The nine lifecycle phases the seed step captures (FR-021, FR-032).
# Order matches `contracts/config-schema.json` and the data-model doc.
readonly -a CONFIG_WORKFLOW_PHASES=(
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

# The three stock team states task-phase sub-issues use (FR-005, data
# model § 3.5). Distinct from the nine spec-lifecycle phases above.
readonly -a CONFIG_DEFAULT_STATE_KEYS=(
    "todo"
    "in_progress"
    "done"
)

# Agent identity families recognised by the v1 reconcile path (FR-036).
# Anything outside this list still resolves via the AGENT_NAME env-var
# fallback in reconcile::_resolve_running_agent, lazy-minting an
# `agent:<lowercased-first-word>` label at sync time; the seed step only
# captures UUIDs for the v1 canonical families up-front.
readonly -a CONFIG_AGENT_FAMILIES=(
    "claude"
    "codex"
)

# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------

# config::_die <message...>
# Print a structured, operator-actionable error to stderr and exit 2
# (the FR-022 / Principle VIII halt code). All public-API error paths
# funnel through here.
config::_die() {
    local message="$*"
    printf 'spec-kit-linear: config: %s\n' "${message}" >&2
    exit 2
}

# config::_warn <message...>
# Non-fatal companion to `_die` — for cases where the caller wants the
# diagnostic but is responsible for the exit decision (e.g.
# `config::validate` accumulates several issues before exiting).
config::_warn() {
    local message="$*"
    printf 'spec-kit-linear: config: %s\n' "${message}" >&2
}

# config::_strip <raw>
# Trim leading + trailing whitespace and unwrap surrounding single or
# double quotes from a YAML scalar. Comments after `#` are stripped
# upstream in `_parse_file` before this is called.
config::_strip() {
    local value="${1-}"
    # leading whitespace
    value="${value#"${value%%[![:space:]]*}"}"
    # trailing whitespace
    value="${value%"${value##*[![:space:]]}"}"
    # surrounding double quotes
    if [[ "${value}" == \"*\" ]]; then
        value="${value#\"}"
        value="${value%\"}"
    # surrounding single quotes
    elif [[ "${value}" == \'*\' ]]; then
        value="${value#\'}"
        value="${value%\'}"
    fi
    printf '%s' "${value}"
}

# config::_parse_file <path>
# Populate CONFIG_VALUES from a shallow YAML file. The grammar we
# accept matches `config-template.yml`:
#
#   key: value                      # scalar at the current indent level
#   key:                            # nested-block opener
#     child: value                  # child of the most recent opener
#   - item                          # list item under the most recent opener
#
# Two indentation levels are supported (top-level keys plus one nested
# block, with `workflow_state_uuids` / `default_state_uuids` being
# flat maps that live one level deeper than their parent). That is the
# entire shape `config-template.yml` ever produces, so we don't try to
# be a general-purpose YAML parser.
#
# <target-array> (optional, default CONFIG_VALUES) names the associative
# array the parsed key→value pairs land in, via a bash nameref. This
# lets the operator-local identity file (spec 004) reuse the exact same
# shallow reader, populating CONFIG_OPERATOR_VALUES instead.
config::_parse_file() {
    local path="$1"
    local -n _cfg_target="${2:-CONFIG_VALUES}"
    local line raw_key raw_value
    local indent
    # Parallel arrays simulating a stack: stack[i] is the YAML key at
    # depth i; indents[i] is the column at which that key's CHILDREN
    # must sit. depth is the count of currently-open blocks.
    local -a stack=()
    local -a indents=()
    local depth=0
    local current_prefix=""
    local list_counter=0

    while IFS= read -r line || [[ -n "${line}" ]]; do
        # Strip trailing CR (Windows-friendly).
        line="${line%$'\r'}"

        # Drop trailing comments. We're permissive: any `#` not inside
        # a balanced-quote run is treated as a comment. The config
        # template never embeds `#` inside scalar values, so the simple
        # split below is safe.
        if [[ "${line}" == *'#'* ]]; then
            local before_hash="${line%%#*}"
            local dq="${before_hash//[^\"]/}"
            local sq="${before_hash//[^\']/}"
            if (( ${#dq} % 2 == 0 )) && (( ${#sq} % 2 == 0 )); then
                line="${before_hash}"
            fi
        fi

        # Skip blank lines.
        if [[ -z "${line//[[:space:]]/}" ]]; then
            continue
        fi

        # Compute leading indent (spaces only; tabs are rejected to
        # keep the operator-edit path predictable).
        if [[ "${line}" == *$'\t'* ]]; then
            config::_die "${path}: tab character in indentation; use spaces only"
        fi
        local lstripped="${line#"${line%%[![:space:]]*}"}"
        indent=$(( ${#line} - ${#lstripped} ))

        # Pop the indent stack until the top frame's child-indent is
        # strictly less than the current line's indent (i.e. the
        # current line is a child of the surviving top frame, or a
        # sibling of the popped one).
        while (( depth > 0 )) && (( indents[depth-1] >= indent )); do
            depth=$(( depth - 1 ))
            unset 'stack[depth]'
            unset 'indents[depth]'
        done

        # Rebuild current_prefix from the surviving stack.
        current_prefix=""
        local d
        for (( d = 0; d < depth; d++ )); do
            if [[ -z "${current_prefix}" ]]; then
                current_prefix="${stack[d]}"
            else
                current_prefix="${current_prefix}.${stack[d]}"
            fi
        done

        # List item under the most-recently-opened block.
        if [[ "${lstripped}" == -* ]]; then
            if [[ -z "${current_prefix}" ]]; then
                config::_die "${path}: list item outside any block: ${lstripped}"
            fi
            local item="${lstripped#-}"
            item="$(config::_strip "${item}")"
            _cfg_target["${current_prefix}.${list_counter}"]="${item}"
            list_counter=$(( list_counter + 1 ))
            continue
        fi

        # key:value or key:  (block opener)
        if [[ "${lstripped}" != *:* ]]; then
            config::_die "${path}: malformed line (no key:value separator): ${lstripped}"
        fi

        raw_key="${lstripped%%:*}"
        raw_value="${lstripped#*:}"
        raw_key="$(config::_strip "${raw_key}")"
        raw_value="$(config::_strip "${raw_value}")"

        local full_key
        if [[ -z "${current_prefix}" ]]; then
            full_key="${raw_key}"
        else
            full_key="${current_prefix}.${raw_key}"
        fi

        if [[ -z "${raw_value}" ]]; then
            # Block opener — push onto the stack and reset the list
            # counter in case the next non-blank line is a list item.
            stack[depth]="${raw_key}"
            indents[depth]="${indent}"
            depth=$(( depth + 1 ))
            current_prefix="${full_key}"
            list_counter=0
        else
            _cfg_target["${full_key}"]="${raw_value}"
        fi
    done < "${path}"
}

# ---------------------------------------------------------------------------
# Public API.
# ---------------------------------------------------------------------------

# config::load <path>
# Parse the YAML at <path> and populate module state. Halts with exit
# 2 if the file is missing or unreadable. Other parse failures funnel
# through `config::_die`.
config::load() {
    if (( $# != 1 )); then
        config::_die "config::load requires exactly one argument (path to linear-config.yml)"
    fi

    local path="$1"

    if [[ ! -e "${path}" ]]; then
        config::_die "file not found: ${path}
hint: copy config-template.yml to ${path} and run \`/spec-kit-linear-install\` to populate UUIDs"
    fi

    if [[ ! -r "${path}" ]]; then
        config::_die "file not readable: ${path}"
    fi

    # Reset state so consecutive loads in the same process don't leak.
    CONFIG_VALUES=()
    CONFIG_OPERATOR_VALUES=()
    CONFIG_LOADED_PATH="${path}"
    CONFIG_OPERATOR_LOADED_PATH=""

    config::_parse_file "${path}" CONFIG_VALUES

    # spec 004 — back-compat migration. A legacy single-file config that
    # still carries `linear.operator.*` keys is migrated out: identity is
    # moved into the operator-local file and the `operator:` block is
    # stripped from the committed file, with exactly one notice (FR-007).
    # Runs BEFORE the operator-local load so a freshly-migrated identity is
    # immediately visible to the cascade in this same process.
    config::_maybe_migrate_operator_block "${path}"

    # spec 004 — load the operator-local identity store (env → file
    # cascade is applied at getter time). Absent file is a no-op.
    config::_load_operator_file
}

# config::_load_operator_file [path]
# Parse the operator-local identity file (default
# CONFIG_OPERATOR_LOCAL_PATH_DEFAULT) into CONFIG_OPERATOR_VALUES. An
# absent file is a silent no-op (identity then resolves from env or
# degrades gracefully per FR-011). A present-but-unreadable or malformed
# file surfaces the SAME actionable diagnostic the committed loader emits
# (Principle VIII — no silent failure).
# shellcheck disable=SC2120  # the optional [path] arg is intentional (exercised
# by unit tests); no runtime caller passes one, which is fine.
config::_load_operator_file() {
    local path="${1:-${CONFIG_OPERATOR_LOCAL_PATH_DEFAULT}}"

    CONFIG_OPERATOR_VALUES=()
    CONFIG_OPERATOR_LOADED_PATH=""

    if [[ ! -e "${path}" ]]; then
        return 0
    fi
    if [[ ! -r "${path}" ]]; then
        config::_die "operator-local file not readable: ${path}"
    fi

    CONFIG_OPERATOR_LOADED_PATH="${path}"
    config::_parse_file "${path}" CONFIG_OPERATOR_VALUES
}

# config::operator_loaded_path
# Echo the path of the operator-local file that populated the identity
# store, or empty if none was loaded. Diagnostic accessor (parity with
# CONFIG_LOADED_PATH); used by tests asserting the cascade source.
config::operator_loaded_path() {
    printf '%s\n' "${CONFIG_OPERATOR_LOADED_PATH}"
}

# config::_maybe_migrate_operator_block <committed-path>
# Detect a legacy `linear.operator.*` key in the just-parsed committed
# config. If present:
#   1. Move the identity into the operator-local file — but ONLY when
#      that file does not already exist (the local file is authoritative
#      per the spec's edge cases; legacy values are otherwise dropped).
#   2. Strip the `operator:` block from the committed file in place.
#   3. Emit exactly one migration notice (latched).
# Idempotent: step 2 removes the trigger so a later run never re-fires.
config::_maybe_migrate_operator_block() {
    local committed_path="$1"

    local legacy_user_id="${CONFIG_VALUES[linear.operator.user_id]:-}"
    local legacy_name="${CONFIG_VALUES[linear.operator.name]:-}"
    local legacy_email="${CONFIG_VALUES[linear.operator.email]:-}"

    # No legacy block → nothing to migrate (the common, post-split case).
    if [[ -z "${legacy_user_id}" && -z "${legacy_name}" && -z "${legacy_email}" ]]; then
        return 0
    fi

    local local_path="${CONFIG_OPERATOR_LOCAL_PATH_DEFAULT}"

    # 1. Write the operator-local file from the legacy values, only when
    #    no operator-local file exists yet (local file wins if present).
    if [[ ! -e "${local_path}" ]]; then
        local dir
        dir="$(dirname "${local_path}")"
        mkdir -p "${dir}" 2>/dev/null || true
        {
            printf '# spec-kit-linear — operator-local identity (NEVER COMMIT).\n'
            printf '# Migrated from a legacy linear-config.yml operator block (spec 004, FR-007).\n'
            printf '# Resolution cascade: LINEAR_OPERATOR_USER_ID env -> this file -> prompt.\n'
            printf 'schema_version: 1\n'
            printf 'operator:\n'
            printf '  user_id: "%s"\n' "${legacy_user_id}"
            printf '  name: "%s"\n' "${legacy_name}"
            printf '  email: "%s"\n' "${legacy_email}"
        } > "${local_path}"
    fi

    # 2. Strip the `operator:` block from the committed file in place. The
    #    block is a one-level child of `linear:` (two-space indent); its
    #    children sit at four-space indent. Portable awk, matching the
    #    style of install.sh's field substituters.
    if [[ -w "${committed_path}" ]]; then
        local tmp
        tmp="$(mktemp -t spec-kit-linear-config.XXXXXX 2>/dev/null || mktemp)"
        awk '
            BEGIN { in_op = 0 }
            {
                # The operator: block opener at the two-space indent.
                if ($0 ~ /^  operator:[[:space:]]*$/) {
                    in_op = 1
                    next
                }
                if (in_op == 1) {
                    # Children of operator: sit deeper than two spaces.
                    # A blank line inside the block is also dropped.
                    if ($0 ~ /^    / || $0 ~ /^[[:space:]]*$/) {
                        next
                    }
                    # Any line at the two-space (sibling) indent or
                    # shallower closes the block; fall through to print it.
                    in_op = 0
                }
                print
            }
        ' "${committed_path}" > "${tmp}" && mv "${tmp}" "${committed_path}"
        # Drop the now-stale legacy keys from the in-memory committed store
        # so getters that still read CONFIG_VALUES never see identity.
        unset 'CONFIG_VALUES[linear.operator.user_id]'
        unset 'CONFIG_VALUES[linear.operator.name]'
        unset 'CONFIG_VALUES[linear.operator.email]'
    fi

    # 3. Emit exactly one migration notice.
    if (( _CONFIG_MIGRATION_NOTICE_EMITTED == 0 )); then
        config::_warn "migrated operator identity out of ${committed_path} into ${local_path} (spec 004, FR-007); the committed config no longer carries operator.* keys. Commit ${committed_path}; do not commit ${local_path} (it is gitignored)."
        _CONFIG_MIGRATION_NOTICE_EMITTED=1
    fi
}

# config::_require_loaded
# Internal guard for every getter. Refuses to operate on empty state.
config::_require_loaded() {
    if [[ -z "${CONFIG_LOADED_PATH}" ]]; then
        config::_die "no config loaded; call \`config::load <path>\` first"
    fi
}

# config::get_team_id
# Echo the Linear team UUID. Halts if the field is absent.
config::get_team_id() {
    config::_require_loaded
    local value="${CONFIG_VALUES[linear.team.id]:-}"
    if [[ -z "${value}" ]]; then
        config::_die "${CONFIG_LOADED_PATH}: linear.team.id is missing"
    fi
    printf '%s\n' "${value}"
}

# config::get_project_id
# Echo the Linear project UUID. Halts if the field is absent.
config::get_project_id() {
    config::_require_loaded
    local value="${CONFIG_VALUES[linear.project.id]:-}"
    if [[ -z "${value}" ]]; then
        config::_die "${CONFIG_LOADED_PATH}: linear.project.id is missing"
    fi
    printf '%s\n' "${value}"
}

# config::resolve_operator_user_id
# Resolve the Linear operator UUID via the spec-004 cascade:
#   1. LINEAR_OPERATOR_USER_ID environment variable (highest — CI /
#      ephemeral override, matching the LINEAR_API_KEY env-first model).
#   2. operator.user_id from the operator-local file
#      (CONFIG_OPERATOR_VALUES).
#   3. empty — the caller (reconcile) warns and proceeds creating Issues
#      unassigned (FR-011); never a halt.
# MUST NOT read identity from the committed config (CONFIG_VALUES) — that
# would re-introduce the leak this feature removes (FR-005).
# Interactive prompting is the install/caller's responsibility; this
# resolver is non-interactive and returns empty when nothing resolves.
config::resolve_operator_user_id() {
    if [[ -n "${LINEAR_OPERATOR_USER_ID:-}" ]]; then
        printf '%s\n' "${LINEAR_OPERATOR_USER_ID}"
        return 0
    fi
    printf '%s\n' "${CONFIG_OPERATOR_VALUES[operator.user_id]:-}"
}

# config::get_operator_user_id
# Back-compat accessor (FR-009). Same cascade as
# config::resolve_operator_user_id; retained so existing callers/tests
# keep working. Empty (no halt) when absent — the reconciler treats
# absence as a warning and creates Issues unassigned per FR-011.
config::get_operator_user_id() {
    config::_require_loaded
    config::resolve_operator_user_id
}

# config::get_operator_name
# Echo the operator's display name from the operator-local store, or the
# LINEAR_OPERATOR_NAME env override. Informational; empty if absent.
config::get_operator_name() {
    config::_require_loaded
    if [[ -n "${LINEAR_OPERATOR_NAME:-}" ]]; then
        printf '%s\n' "${LINEAR_OPERATOR_NAME}"
        return 0
    fi
    printf '%s\n' "${CONFIG_OPERATOR_VALUES[operator.name]:-}"
}

# config::get_operator_email
# Echo the operator's email from the operator-local store, or the
# LINEAR_OPERATOR_EMAIL env override. Informational (surfaced in the
# memory block "last touched by" cell); empty if absent.
config::get_operator_email() {
    config::_require_loaded
    if [[ -n "${LINEAR_OPERATOR_EMAIL:-}" ]]; then
        printf '%s\n' "${LINEAR_OPERATOR_EMAIL}"
        return 0
    fi
    printf '%s\n' "${CONFIG_OPERATOR_VALUES[operator.email]:-}"
}

# config::get_workflow_state_uuid <lifecycle_phase>
# Echo the workflow-state UUID for one of the nine lifecycle phases
# (specifying|clarifying|planning|tasking|red_team|implementing|
# analyzing|ready_to_merge|merged). Halts on unknown phase or missing
# UUID with a remediation pointer to `speckit.linear.seed`.
config::get_workflow_state_uuid() {
    config::_require_loaded
    if (( $# != 1 )); then
        config::_die "config::get_workflow_state_uuid requires exactly one argument (lifecycle phase)"
    fi

    local phase="$1"
    local known=0
    local candidate
    for candidate in "${CONFIG_WORKFLOW_PHASES[@]}"; do
        if [[ "${candidate}" == "${phase}" ]]; then
            known=1
            break
        fi
    done

    if (( known == 0 )); then
        config::_die "unknown lifecycle phase: ${phase}
hint: valid phases are ${CONFIG_WORKFLOW_PHASES[*]}"
    fi

    local value="${CONFIG_VALUES[linear.workflow_state_uuids.${phase}]:-}"
    if [[ -z "${value}" ]]; then
        config::_die "${CONFIG_LOADED_PATH}: linear.workflow_state_uuids.${phase} is missing
hint: run \`/spec-kit-linear-seed\` to re-capture workflow-state UUIDs"
    fi
    printf '%s\n' "${value}"
}

# config::get_default_state_uuid <todo|in_progress|done>
# Echo the UUID for one of the three stock team states task-phase
# sub-issues use (FR-005). The `default_state_uuids` block is added
# during the post-analyze remediation; if absent, surface the gap.
config::get_default_state_uuid() {
    config::_require_loaded
    if (( $# != 1 )); then
        config::_die "config::get_default_state_uuid requires exactly one argument (todo|in_progress|done)"
    fi

    local key="$1"
    local known=0
    local candidate
    for candidate in "${CONFIG_DEFAULT_STATE_KEYS[@]}"; do
        if [[ "${candidate}" == "${key}" ]]; then
            known=1
            break
        fi
    done

    if (( known == 0 )); then
        config::_die "unknown default-state key: ${key}
hint: valid keys are ${CONFIG_DEFAULT_STATE_KEYS[*]}"
    fi

    local value="${CONFIG_VALUES[linear.default_state_uuids.${key}]:-}"
    if [[ -z "${value}" ]]; then
        config::_die "${CONFIG_LOADED_PATH}: linear.default_state_uuids.${key} is missing
hint: run \`/spec-kit-linear-seed\` to capture stock team-state UUIDs (todo/in_progress/done)"
    fi
    printf '%s\n' "${value}"
}

# config::get_agent_label_uuid <agent_family>
# Echo the workspace label UUID for one of the canonical agent families
# (`claude`, `codex`) captured by /spec-kit-linear-seed (FR-036). The
# accessor is asymmetric on purpose:
#   * Empty <agent_family> ⇒ echo empty + return 0. This is the
#     "no AGENT_NAME / CLAUDE_CODE_MODEL / CODEX_MODEL env var resolved"
#     graceful-degradation path described in FR-036 — the bridge MUST
#     keep working when the running shell has no AI agent context, just
#     without an `agent:*` stamp.
#   * Block missing AND non-empty <agent_family> ⇒ halt with a clear
#     remediation pointer. An operator who has an AI agent active but
#     hasn't re-run seed since FR-036 landed needs a hard nudge, not a
#     silent skip; lookups-by-UUID-not-name (Principle V) means we can't
#     safely guess the UUID at reconcile time.
#   * Block present but family key absent ⇒ echo empty + return 0. This
#     is the "unrecognised agent" case (e.g. AGENT_NAME=gemini); the
#     resolver upstream lazy-mints `agent:gemini` via Linear's standard
#     issueLabelCreate path so v1 never has to ship every possible
#     agent family up-front.
config::get_agent_label_uuid() {
    config::_require_loaded
    if (( $# != 1 )); then
        config::_die "config::get_agent_label_uuid requires exactly one argument (agent family, e.g. 'claude')"
    fi

    local family="$1"

    # Graceful degradation when the resolver upstream couldn't identify
    # the running agent (no env var matched). Empty family ⇒ empty
    # output ⇒ caller omits the label stamp entirely.
    if [[ -z "$family" ]]; then
        printf ''
        return 0
    fi

    # Detect "block entirely missing" by checking whether ANY family key
    # has been parsed under linear.agent_label_uuids.*. If at least one
    # is present, the seed step has clearly run post-FR-036; if none are,
    # the operator needs to re-seed before stamping can work.
    local block_present=0
    local probe
    for probe in "${CONFIG_AGENT_FAMILIES[@]}"; do
        if [[ -n "${CONFIG_VALUES[linear.agent_label_uuids.${probe}]:-}" ]]; then
            block_present=1
            break
        fi
    done

    if (( block_present == 0 )); then
        config::_die "${CONFIG_LOADED_PATH}: linear.agent_label_uuids block is missing but an agent identifier ('${family}') was resolved
hint: run \`/spec-kit-linear-seed\` to create the agent:* labels and capture their UUIDs (FR-036)"
    fi

    # Block present but this specific family was not seeded — silently
    # return empty. The reconciler's _resolve_agent_label_id helper will
    # treat this as "no canonical UUID; fall back to lazy-create by name".
    printf '%s\n' "${CONFIG_VALUES[linear.agent_label_uuids.${family}]:-}"
}

# config::validate
# Confirm every required UUID is present and well-formed. Returns 0 on
# success; on failure, prints a list of missing/malformed fields to
# stderr (each prefixed with the source file path so the operator can
# jump straight to the offending line) and exits 2.
#
# Required fields:
#   schema_version                                 (must equal 1)
#   linear.team.id                                 (UUID)
#   linear.project.id                              (UUID)
#   linear.workflow_state_uuids.<each of 9>        (UUID)
#   linear.default_state_uuids.<each of 3>         (UUID; only checked if the block is present)
#
# `default_state_uuids` is treated as optional-but-validated: missing
# block → soft warning so old configs still load; partial block →
# hard failure so half-finished seeds can't ship.
config::validate() {
    config::_require_loaded

    local -a problems=()
    local path="${CONFIG_LOADED_PATH}"

    # schema_version sanity check (the JSON Schema pins it to 1).
    local schema_version="${CONFIG_VALUES[schema_version]:-}"
    if [[ -z "${schema_version}" ]]; then
        problems+=("${path}: schema_version: missing (expected 1)")
    elif [[ "${schema_version}" != "1" ]]; then
        problems+=("${path}: schema_version: got '${schema_version}', expected 1")
    fi

    # team + project UUIDs.
    local field
    for field in "linear.team.id" "linear.project.id"; do
        local value="${CONFIG_VALUES[${field}]:-}"
        if [[ -z "${value}" ]]; then
            problems+=("${path}: ${field}: missing")
        elif ! [[ "${value}" =~ ${CONFIG_UUID_REGEX} ]]; then
            problems+=("${path}: ${field}: malformed UUID ('${value}')")
        elif [[ "${value}" == "00000000-0000-0000-0000-000000000000" ]]; then
            problems+=("${path}: ${field}: still set to the zero placeholder UUID; run \`/spec-kit-linear-install\` to resolve it")
        fi
    done

    # workflow_state_uuids — all nine required.
    local phase
    for phase in "${CONFIG_WORKFLOW_PHASES[@]}"; do
        local key="linear.workflow_state_uuids.${phase}"
        local value="${CONFIG_VALUES[${key}]:-}"
        if [[ -z "${value}" ]]; then
            problems+=("${path}: ${key}: missing (run \`/spec-kit-linear-seed\`)")
        elif ! [[ "${value}" =~ ${CONFIG_UUID_REGEX} ]]; then
            problems+=("${path}: ${key}: malformed UUID ('${value}')")
        elif [[ "${value}" == "00000000-0000-0000-0000-000000000000" ]]; then
            problems+=("${path}: ${key}: still set to the zero placeholder UUID; run \`/spec-kit-linear-seed\`")
        fi
    done

    # default_state_uuids — optional block, but if any key is present
    # ALL three must be present + well-formed.
    local default_block_present=0
    local default_key
    for default_key in "${CONFIG_DEFAULT_STATE_KEYS[@]}"; do
        if [[ -n "${CONFIG_VALUES[linear.default_state_uuids.${default_key}]:-}" ]]; then
            default_block_present=1
            break
        fi
    done

    if (( default_block_present == 1 )); then
        for default_key in "${CONFIG_DEFAULT_STATE_KEYS[@]}"; do
            local dkey="linear.default_state_uuids.${default_key}"
            local dvalue="${CONFIG_VALUES[${dkey}]:-}"
            if [[ -z "${dvalue}" ]]; then
                problems+=("${path}: ${dkey}: missing (partial default_state_uuids block)")
            elif ! [[ "${dvalue}" =~ ${CONFIG_UUID_REGEX} ]]; then
                problems+=("${path}: ${dkey}: malformed UUID ('${dvalue}')")
            elif [[ "${dvalue}" == "00000000-0000-0000-0000-000000000000" ]]; then
                problems+=("${path}: ${dkey}: still set to the zero placeholder UUID; run \`/spec-kit-linear-seed\`")
            fi
        done
    fi

    if (( ${#problems[@]} > 0 )); then
        config::_warn "validation failed for ${path}:"
        local problem
        for problem in "${problems[@]}"; do
            printf '  - %s\n' "${problem}" >&2
        done
        exit 2
    fi

    return 0
}
