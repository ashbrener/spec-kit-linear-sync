#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# src/summary.sh — structured summary emitter (Principle VIII)
#
# Every reconcile invocation MUST end with a structured, named-warning summary
# (constitution v1.0.0 Principle VIII; spec FR-023, FR-024). This module owns
# that contract. It is sourced — never executed — by:
#
#   * src/reconcile.sh    — the main reconciler (Layer D)
#   * src/install.sh      — install ceremony
#   * src/seed.sh         — workspace seed
#   * tests/unit/summary.bats — unit coverage
#
# Public API (all functions are namespaced `summary::*`):
#
#   summary::start [<title>]
#       Initialise module-level counters and the warning/message buffer.
#       Optional <title> is printed at the top of the emitted block (e.g. the
#       caller may pass "speckit.linear reconcile — repo: foo, branch: 001-…").
#       Safe to call multiple times in the same process; each call resets state.
#
#   summary::add <type> <message>
#       Record an event. <type> MUST be one of:
#         created | updated | archived | warned | skipped | error | info
#       Always increments the per-type counter. For warned / skipped / error
#       the <message> is also appended to the warning/message buffer rendered
#       in the `----- warnings -----` section of the emitted block. For `info`
#       (spec 003 / drift-warning-surface §7 — e.g. the --retroactive
#       deprecation notice) the <message> is appended to a separate INFO
#       buffer rendered as top-of-summary `INFO` lines, just under the title.
#       created / updated / archived messages are counter-only; their text is
#       discarded to keep the summary block scannable (the structured count is
#       the contract, not per-event lines).
#
#   summary::emit
#       Print the final structured block to stderr (per Principle VIII Rule 1
#       and spec FR-023 — the summary is operator-facing observability, not
#       data piped to a downstream consumer; stdout stays clean for any future
#       script that pipes reconcile output). ANSI colour is applied to counter
#       LABELS only when stderr is a tty (`[ -t 2 ]`). No colour when stderr
#       is redirected to a file or another process.
#
#   summary::has_errors
#       Returns 0 (true) if any `error` events were recorded since the last
#       `summary::start`; returns 1 (false) otherwise. Use as the exit-status
#       hook for callers that want a non-zero exit on any error event.
#
#   summary::count <type>
#       Echoes the current count for <type>. Unknown types echo 0.
#
# Design notes:
#
#   * Bash 4+ associative arrays back the counters; the project's install step
#     already refuses macOS bash 3.2 (per plan.md Technical Context), so we
#     can rely on this without a fallback.
#   * No global state outside the `_SUMMARY_*` prefix — keeps this module safe
#     to source repeatedly without polluting the caller's namespace.
#   * Colour codes use `printf '\033[...m'` directly rather than `tput`. tput
#     requires a working TERM entry and is noisier under bats; raw escapes are
#     fine for the narrow `green / yellow / red` palette we need.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Module-private state. All names share the `_SUMMARY_` prefix so the caller
# can `set +u` / `set -u` around us without colliding on unset reads.
# -----------------------------------------------------------------------------

# Counter map, keyed by event type. Re-initialised by summary::start.
#
# NOTE (subshell durability — issue #36): bash associative arrays live in the
# shell that declares them and are COPIED, never shared back, into any `$(…)`
# command substitution. The reconciler creates issues/sub-issues inside deeply
# nested command substitutions (reconcile::sync_spec_issue / …_subissues are
# themselves `$(…)`-captured, and each calls reconcile::mutate_issue_create in
# yet another `$(…)`), so every `summary::add created` increment happened in a
# throwaway subshell and was lost before `summary::emit` ran in the parent —
# the summary reported `Created: 0` even after creating issues. To make the
# counts durable across subshell boundaries we ALSO append every event to an
# on-disk tally file (one event type per line); summary::count / summary::emit
# / summary::has_errors aggregate from that file so subshell increments survive.
# The in-memory map is kept as a same-shell fast path / fallback.
declare -gA _SUMMARY_COUNTS=()

# Path to the append-only tally file backing the counters across subshells.
# Set by summary::start; appended to by summary::add; read by summary::count,
# summary::has_errors, and summary::emit. Empty when start has not run (the
# lazy-init paths set it).
declare -g _SUMMARY_TALLY_FILE=""

# Ordered list of warning/skipped/error messages, in insertion order. Rendered
# under `----- warnings -----` by summary::emit.
declare -ga _SUMMARY_WARNINGS=()

# Ordered list of INFO messages (spec 003 / drift-warning-surface §7), in
# insertion order. Rendered as top-of-summary `INFO  <message>` lines, just
# under the optional title and above the counter rows.
declare -ga _SUMMARY_INFOS=()

# Optional header line printed at the top of the emitted block.
declare -g _SUMMARY_TITLE=""

# Sentinel set by summary::start so summary::emit can detect "called without a
# prior start" and still produce a valid (zero-everything) block rather than
# crashing on unbound-variable access.
declare -g _SUMMARY_INITIALISED="false"

# -----------------------------------------------------------------------------
# summary::_supports_colour
#   Internal: returns 0 if stderr is a tty AND NO_COLOR is unset / empty.
#   Honours the de-facto `NO_COLOR` convention (https://no-color.org/) so an
#   operator who explicitly opts out of colour gets monochrome even on a tty.
# -----------------------------------------------------------------------------
summary::_supports_colour() {
    # `[ -t 2 ]` is the canonical "stderr is a terminal" probe. If stderr is
    # redirected (e.g. `reconcile 2> log.txt` or `reconcile 2>&1 | tee`), this
    # returns 1 and we emit plain text — colour codes in a log file are noise.
    if [[ -n "${NO_COLOR:-}" ]]; then
        return 1
    fi
    if [[ -t 2 ]]; then
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# summary::_colour <ansi-code> <text>
#   Internal: wraps <text> in the given ANSI sequence iff colour is supported.
#   <ansi-code> is the numeric part (e.g. 32 for green); the function adds the
#   ESC[...m prefix and the ESC[0m reset.
# -----------------------------------------------------------------------------
summary::_colour() {
    local code="$1"
    local text="$2"
    if summary::_supports_colour; then
        printf '\033[%sm%s\033[0m' "$code" "$text"
    else
        printf '%s' "$text"
    fi
}

# -----------------------------------------------------------------------------
# summary::start [<title>]
# -----------------------------------------------------------------------------
summary::start() {
    # Reset every counter explicitly rather than `unset` + redeclare, so the
    # module remains usable across multiple start/emit cycles in one process
    # (e.g. a long-running test runner).
    _SUMMARY_COUNTS=(
        [created]=0
        [updated]=0
        [archived]=0
        [warned]=0
        [skipped]=0
        [error]=0
        [info]=0
    )
    _SUMMARY_WARNINGS=()
    _SUMMARY_INFOS=()
    _SUMMARY_TITLE="${1:-}"
    _SUMMARY_INITIALISED="true"

    # Create (or reset) the append-only tally file that makes counters durable
    # across `$(…)` subshells (issue #36). One event type is appended per line
    # by summary::add; the aggregators count occurrences. We create it here so
    # the path is shared with any subshell forked AFTER start — a subshell
    # inherits the exported variable and appends to the same inode, so its
    # increments reach the parent's summary::emit. Truncate on every start so
    # repeated start/emit cycles in one process don't accumulate stale events.
    if [[ -z "$_SUMMARY_TALLY_FILE" ]] || [[ ! -e "$_SUMMARY_TALLY_FILE" ]]; then
        _SUMMARY_TALLY_FILE="$(mktemp "${TMPDIR:-/tmp}/speckit-linear-summary.XXXXXX")"
    else
        : > "$_SUMMARY_TALLY_FILE"
    fi
    export _SUMMARY_TALLY_FILE
}

# -----------------------------------------------------------------------------
# summary::_tally <type>
#   Internal: append one event <type> to the durable tally file so the count
#   survives the `$(…)` subshell it may have been recorded in (issue #36).
#   Best-effort: a failed append (e.g. tally file missing on a lazy-init edge)
#   must never abort the reconcile, so it falls back silently to the in-memory
#   counter that summary::add already bumped.
# -----------------------------------------------------------------------------
summary::_tally() {
    local type="$1"
    # SCOPE (issue #36): only the `created` counter is made subshell-durable.
    # That is the single counter the bug report identifies as under-reporting,
    # and it is the only one the reconciler bumps exclusively from inside
    # `$(…)` command substitutions (every issue/sub-issue create). Other
    # counters (updated/archived/warned/skipped/error/info) keep their existing
    # in-memory semantics verbatim — widening the durable set would also revive
    # error/exit-code promotions that other call paths intentionally scope to
    # their subshell, which is out of scope for this fix.
    [[ "$type" == "created" ]] || return 0
    [[ -n "$_SUMMARY_TALLY_FILE" ]] || return 0
    printf '%s\n' "$type" >> "$_SUMMARY_TALLY_FILE" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# summary::_count_from_tally <type>
#   Internal: echo the durable count for <type> by tallying the on-disk file,
#   falling back to the in-memory counter when no tally file is present (e.g.
#   a caller that bumped the array directly, or a lazy-init edge). The on-disk
#   value is authoritative when it exists because it folds in increments made
#   inside subshells that the in-memory array never saw.
# -----------------------------------------------------------------------------
summary::_count_from_tally() {
    local type="$1"
    # Only `created` is tally-backed (see summary::_tally scope note). For the
    # durable counter, the on-disk file is authoritative because it folds in
    # the subshell increments the in-memory array never saw. All other types
    # read straight from the in-memory map, exactly as before this fix.
    if [[ "$type" == "created" \
        && -n "$_SUMMARY_TALLY_FILE" && -r "$_SUMMARY_TALLY_FILE" ]]; then
        # `grep -c` always prints a single count (0 on no match) and exits 1
        # when the count is zero — so we must NOT add a `|| printf 0` fallback,
        # or a no-match would print "0" from grep AND "0" from the fallback.
        # The `|| true` only neutralises the exit status under `set -e`.
        local n
        n="$(grep -c -x -F -- "$type" "$_SUMMARY_TALLY_FILE" 2>/dev/null)" || true
        printf '%s' "${n:-0}"
        return 0
    fi
    printf '%s' "${_SUMMARY_COUNTS[$type]:-0}"
}

# -----------------------------------------------------------------------------
# summary::add <type> <message>
# -----------------------------------------------------------------------------
summary::add() {
    local type="${1:-}"
    local message="${2:-}"

    # Lazy-init so callers that forgot summary::start still get a coherent
    # block; emit a warning event to surface the misuse rather than failing
    # silently (Principle VIII — observable failure). We explicitly pass no
    # arguments through (summary::add's $1/$2 are type/message, not a title)
    # but spelling it as `summary::start ""` keeps shellcheck SC2119 quiet
    # without forwarding our own positional args into the lazy-init path.
    if [[ "$_SUMMARY_INITIALISED" != "true" ]]; then
        summary::start ""
        _SUMMARY_WARNINGS+=("summary::add called before summary::start; auto-initialised")
        _SUMMARY_COUNTS[warned]=$(( ${_SUMMARY_COUNTS[warned]:-0} + 1 ))
    fi

    case "$type" in
        created|updated|archived|warned|skipped|error|info)
            _SUMMARY_COUNTS[$type]=$(( ${_SUMMARY_COUNTS[$type]:-0} + 1 ))
            # Durable tally (issue #36): record the event so increments made
            # inside a `$(…)` subshell still reach the parent's summary::emit.
            summary::_tally "$type"
            ;;
        *)
            # Unknown type — treat as a warning event so it is loud rather
            # than silently dropped. Principle VIII: surface, don't enforce.
            _SUMMARY_COUNTS[warned]=$(( ${_SUMMARY_COUNTS[warned]:-0} + 1 ))
            _SUMMARY_WARNINGS+=("summary::add called with unknown type '$type': $message")
            return 0
            ;;
    esac

    # warned / skipped / error contribute to the warnings list; info
    # contributes to the top-of-summary INFO list (drift-warning-surface §7).
    # Counter-only types (created/updated/archived) discard the message — the
    # summary block is meant to be a scannable digest, not a transcript.
    case "$type" in
        warned|skipped|error)
            _SUMMARY_WARNINGS+=("$message")
            ;;
        info)
            _SUMMARY_INFOS+=("$message")
            ;;
    esac
}

# -----------------------------------------------------------------------------
# summary::count <type>
# -----------------------------------------------------------------------------
summary::count() {
    local type="${1:-}"
    printf '%s\n' "$(summary::_count_from_tally "$type")"
}

# -----------------------------------------------------------------------------
# summary::has_errors
#   Returns 0 if at least one error was recorded, 1 otherwise. The shape
#   matches bash's "true if test passes" convention so the caller can write:
#       if summary::has_errors; then exit 1; fi
# -----------------------------------------------------------------------------
summary::has_errors() {
    local count
    count="$(summary::_count_from_tally error)"
    if (( count > 0 )); then
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# summary::emit
#   Print the structured block to stderr. Format is locked by the spec sample
#   (see specs/001-spec-kit-linear-bridge/spec.md FR-023 commentary):
#
#       ===== speckit.linear summary =====
#       <optional title line>
#       Created: 3   Updated: 12   Archived: 1
#       Skipped: 0   Warned: 2     Errors: 0
#       ----- warnings -----
#       - <message 1>
#       - <message 2>
#       ==================================
#
#   The warnings section is omitted entirely when no warning/skipped/error
#   messages were recorded — a clean reconcile prints just the counters.
# -----------------------------------------------------------------------------
summary::emit() {
    # Defensive: tolerate emit-without-start by lazily initialising. The
    # output will be the zero-everything block, which is the right thing to
    # show if a caller threaded summary::emit through an early-return path.
    # Pass an explicit empty title arg so shellcheck SC2119 doesn't flag the
    # bare call (summary::start's $1 is the optional title).
    if [[ "$_SUMMARY_INITIALISED" != "true" ]]; then
        summary::start ""
    fi

    # Read counts from the durable tally (issue #36) so increments recorded
    # inside `$(…)` subshells — e.g. every issue/sub-issue create — are folded
    # into the emitted block, not silently dropped with the subshell.
    local created updated archived skipped warned errors
    created="$(summary::_count_from_tally created)"
    updated="$(summary::_count_from_tally updated)"
    archived="$(summary::_count_from_tally archived)"
    skipped="$(summary::_count_from_tally skipped)"
    warned="$(summary::_count_from_tally warned)"
    errors="$(summary::_count_from_tally error)"

    # Colour palette (Principle VIII counter coding):
    #   green  (32) — created / updated  — positive progress
    #   yellow (33) — warned / skipped   — operator attention warranted
    #   red    (31) — errors             — something failed
    # archived stays uncoloured: it's a neutral cleanup event, not progress
    # or trouble, and colouring it would dilute the signal of the other two.
    local lbl_created lbl_updated lbl_archived
    local lbl_skipped lbl_warned lbl_errors
    lbl_created=$(summary::_colour 32 "Created:")
    lbl_updated=$(summary::_colour 32 "Updated:")
    lbl_archived="Archived:"
    lbl_skipped=$(summary::_colour 33 "Skipped:")
    lbl_warned=$(summary::_colour 33 "Warned:")
    lbl_errors=$(summary::_colour 31 "Errors:")

    {
        printf '===== speckit.linear summary =====\n'
        if [[ -n "$_SUMMARY_TITLE" ]]; then
            printf '%s\n' "$_SUMMARY_TITLE"
        fi
        # Top-of-summary INFO lines (spec 003 / drift-warning-surface §7),
        # rendered above the counter rows. INFO is not an error severity —
        # legacy --retroactive use is informational, not a warning.
        if (( ${#_SUMMARY_INFOS[@]} > 0 )); then
            local info_msg
            for info_msg in "${_SUMMARY_INFOS[@]}"; do
                printf 'INFO  %s\n' "$info_msg"
            done
        fi
        # Two counter rows. Spacing matches the spec sample so a grep on
        # "Created:" or "Errors:" finds exactly one line per reconcile.
        printf '%s %s   %s %s   %s %s\n' \
            "$lbl_created" "$created" \
            "$lbl_updated" "$updated" \
            "$lbl_archived" "$archived"
        printf '%s %s   %s %s     %s %s\n' \
            "$lbl_skipped" "$skipped" \
            "$lbl_warned" "$warned" \
            "$lbl_errors" "$errors"

        if (( ${#_SUMMARY_WARNINGS[@]} > 0 )); then
            printf -- '----- warnings -----\n'
            local msg
            for msg in "${_SUMMARY_WARNINGS[@]}"; do
                printf -- '- %s\n' "$msg"
            done
        fi
        printf '==================================\n'
    } >&2
}
