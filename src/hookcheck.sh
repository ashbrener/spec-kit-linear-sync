#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# src/hookcheck.sh — auto-sync hook self-healing (spec 014-hook-health).
#
# The only sanctioned community install/update path
# (`specify extension add linear --from <zip> --force`) silently strips the
# bridge's six `after_*` auto-sync hooks from the consumer's
# `.specify/extensions.yml`. Auto-sync then stops firing and the Linear board
# drifts unnoticed. This module makes the bridge SELF-REPORT its own hook
# health on every `speckit.linear.push` (reconcile) and `speckit.linear.status`.
#
# Public surface (namespaced `hookcheck::*`):
#
#   hookcheck::classify <hook> [<yml>]
#       Echo present|disabled|absent for one after_* hook (exit 2 on
#       unreadable/malformed file). Uses the SAME block grammar as
#       install::_hook_already_registered (FR-007), extended to read enabled:.
#
#   hookcheck::assess [<yml>]
#       Echo three lines: overall=<...> / missing=<names> / disabled=<names>.
#       overall ∈ present|partial|none|unverifiable|not_installed. Always exit 0.
#
#   hookcheck::assess_into [<yml>]
#       Same assessment, but sets globals HOOKCHECK_OVERALL,
#       HOOKCHECK_MISSING[] and HOOKCHECK_DISABLED[] for in-process callers
#       (reconcile/status) — avoids fragile stdout re-parsing.
#
#   hookcheck::warn_once <overall> <missing...>
#       Emit ONE structured warning per reconcile run (FR-002/FR-010), gated by
#       the _RECONCILE_HOOKS_WARNED latch. unverifiable → one info row.
#
#   hookcheck::status_line <overall> <missing...> -- <disabled...>
#       Echo the human status health line (FR-006). Never touches exit code.
#
#   hookcheck::offer_selfheal <overall> <missing...>
#       INTERACTIVE-ONLY consented self-heal (FR-009): prompt y/N over the tty,
#       and on consent re-register ALL missing hooks at once via install's
#       idempotent register_after_hooks (preserves enabled:false). Non-
#       interactive runs do nothing. The ONLY mutating function here.
#
#   hookcheck::reconcile_check
#       Convenience: assess_into → warn_once → offer_selfheal. Called once per
#       run from reconcile::main.
#
# Constitutional alignment: surface-don't-enforce (Principle VIII) — the warning
# never blocks; mutation is interactive + consented only; non-interactive never
# mutates. Honours operator-disabled hooks (Principle VII): a `enabled: false`
# hook is "disabled", never "missing", and is never re-enabled.
#
# This module is dependency-light on the warn/detect path (awk + grep only). It
# lazily sources install.sh ONLY when an accepted self-heal needs the writer.
# =============================================================================

set -euo pipefail

# Idempotent include-guard (014) — safe to source twice (offer_selfheal lazily
# sources install.sh, which re-sources shared libs this caller already loaded).
[[ -n "${_HOOKCHECK_SH_LOADED:-}" ]] && return 0
readonly _HOOKCHECK_SH_LOADED=1

HOOKCHECK_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The six after_* hooks. MIRRORS install.sh INSTALL_AFTER_HOOK_NAMES; the
# tests/unit/hookcheck.bats pin test fails if the two ever diverge (FR-007/R6).
readonly -a HOOKCHECK_AFTER_HOOK_NAMES=(
    after_specify
    after_clarify
    after_plan
    after_tasks
    after_implement
    after_analyze
)

# Consumer hook registry. Overridable for tests.
: "${HOOKCHECK_EXTENSIONS_YML:=.specify/extensions.yml}"

# Globals populated by hookcheck::assess_into.
declare -g HOOKCHECK_OVERALL=""
declare -ga HOOKCHECK_MISSING=()
declare -ga HOOKCHECK_DISABLED=()

# -----------------------------------------------------------------------------
# hookcheck::classify <hook> [<yml>]
#
# Classify one after_* hook for the `linear` extension. The awk walk mirrors
# install::_hook_already_registered's block grammar (enter on `^  <hook>:`,
# leave on the next 2-space `^  <key>:` line), tracking each `- extension:`
# entry's name + enabled state so a sibling git entry's `enabled: false` never
# bleeds onto the linear verdict.
# -----------------------------------------------------------------------------
hookcheck::classify() {
    local hook="$1"
    local yml="${2:-$HOOKCHECK_EXTENSIONS_YML}"

    [[ -e "$yml" ]] || { printf 'absent\n'; return 0; }
    [[ -r "$yml" ]] || return 2

    awk -v want="$hook" '
        function finalize() {
            if (cur_ext == "linear") {
                have_linear = 1
                if (cur_enabled == "false") linear_disabled = 1
            }
        }
        function reset_entry() { cur_ext = ""; cur_enabled = "true" }
        BEGIN { in_block = 0; have_linear = 0; linear_disabled = 0; reset_entry() }
        $0 ~ ("^  " want ":[[:space:]]*$") { in_block = 1; reset_entry(); next }
        in_block && /^  [a-zA-Z_]+:[[:space:]]*$/ { finalize(); in_block = 0 }
        in_block && /^  - extension:[[:space:]]*/ {
            finalize(); reset_entry()
            line = $0
            sub(/^.*extension:[[:space:]]*/, "", line)
            sub(/[[:space:]]*$/, "", line)
            cur_ext = line
        }
        in_block && /^[[:space:]]+enabled:[[:space:]]*false[[:space:]]*$/ { cur_enabled = "false" }
        in_block && /^[[:space:]]+enabled:[[:space:]]*true[[:space:]]*$/  { cur_enabled = "true" }
        END {
            if (in_block) finalize()
            if (!have_linear)      { print "absent" }
            else if (linear_disabled) { print "disabled" }
            else                   { print "present" }
        }
    ' "$yml"
}

# -----------------------------------------------------------------------------
# hookcheck::assess_into [<yml>] — sets HOOKCHECK_OVERALL / _MISSING / _DISABLED
# -----------------------------------------------------------------------------
hookcheck::assess_into() {
    local yml="${1:-$HOOKCHECK_EXTENSIONS_YML}"
    HOOKCHECK_OVERALL=""
    HOOKCHECK_MISSING=()
    HOOKCHECK_DISABLED=()

    if [[ ! -e "$yml" ]]; then HOOKCHECK_OVERALL="not_installed"; return 0; fi
    if [[ ! -r "$yml" ]]; then HOOKCHECK_OVERALL="unverifiable"; return 0; fi
    # Readable but with no top-level `hooks:` key → not a parseable hook
    # registry; degrade to "could not verify" rather than misreport "none"
    # (FR-008). A legitimately stripped file still carries the `hooks:` key.
    if ! grep -qE '^hooks:[[:space:]]*$' "$yml"; then
        HOOKCHECK_OVERALL="unverifiable"; return 0
    fi

    local h state
    for h in "${HOOKCHECK_AFTER_HOOK_NAMES[@]}"; do
        if ! state="$(hookcheck::classify "$h" "$yml")"; then
            HOOKCHECK_OVERALL="unverifiable"; return 0
        fi
        case "$state" in
            present)  ;;
            disabled) HOOKCHECK_DISABLED+=("$h") ;;
            absent)   HOOKCHECK_MISSING+=("$h") ;;
            *)        HOOKCHECK_OVERALL="unverifiable"; return 0 ;;
        esac
    done

    if (( ${#HOOKCHECK_MISSING[@]} == 0 )); then
        HOOKCHECK_OVERALL="present"
    elif (( ${#HOOKCHECK_MISSING[@]} == ${#HOOKCHECK_AFTER_HOOK_NAMES[@]} )); then
        HOOKCHECK_OVERALL="none"
    else
        HOOKCHECK_OVERALL="partial"
    fi
    return 0
}

# -----------------------------------------------------------------------------
# hookcheck::assess [<yml>] — stdout form (3 lines). Always exit 0.
# -----------------------------------------------------------------------------
hookcheck::assess() {
    hookcheck::assess_into "${1:-$HOOKCHECK_EXTENSIONS_YML}"
    printf 'overall=%s\n' "$HOOKCHECK_OVERALL"
    printf 'missing=%s\n' "${HOOKCHECK_MISSING[*]:-}"
    printf 'disabled=%s\n' "${HOOKCHECK_DISABLED[*]:-}"
}

# -----------------------------------------------------------------------------
# hookcheck::warn_once <overall> <missing...> — one warning per reconcile run.
# -----------------------------------------------------------------------------
hookcheck::warn_once() {
    local overall="$1"; shift
    local -a missing=("$@")

    [[ "${_RECONCILE_HOOKS_WARNED:-0}" == "0" ]] || return 0

    case "$overall" in
        partial|none)
            summary::add warned \
                "${#missing[@]} auto-sync hook(s) not registered (${missing[*]}); run /speckit.linear.install to restore auto-sync"
            _RECONCILE_HOOKS_WARNED=1
            ;;
        unverifiable)
            summary::add info \
                "could not verify auto-sync hook health (${HOOKCHECK_EXTENSIONS_YML} unreadable or malformed)"
            _RECONCILE_HOOKS_WARNED=1
            ;;
        *)
            : # present / not_installed → no warning
            ;;
    esac
}

# -----------------------------------------------------------------------------
# hookcheck::status_line <overall> <missing...> -- <disabled...>
# Echoes the status health line. MUST NOT change the exit code (R7).
# -----------------------------------------------------------------------------
hookcheck::status_line() {
    local overall="$1"; shift
    local -a missing=() disabled=()
    local seen_sep=0 a
    for a in "$@"; do
        if [[ "$a" == "--" ]]; then seen_sep=1; continue; fi
        if (( seen_sep )); then disabled+=("$a"); else missing+=("$a"); fi
    done

    case "$overall" in
        present)
            if (( ${#disabled[@]} > 0 )); then
                printf 'Auto-sync hooks: all wired (%s intentionally disabled)\n' "${disabled[*]}"
            else
                printf 'Auto-sync hooks: all present\n'
            fi
            ;;
        partial)
            printf 'Auto-sync hooks: partial — missing: %s — run /speckit.linear.install to restore\n' "${missing[*]}"
            ;;
        none)
            printf 'Auto-sync hooks: none registered — run /speckit.linear.install to restore auto-sync\n'
            ;;
        unverifiable)
            printf 'Auto-sync hooks: could not verify (%s unreadable or malformed)\n' "$HOOKCHECK_EXTENSIONS_YML"
            ;;
        not_installed)
            printf 'Auto-sync hooks: extension not installed in this repo\n'
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Interactivity + consent helpers (overridable for tests).
# -----------------------------------------------------------------------------
hookcheck::_is_interactive() {
    [[ "${HOOKCHECK_FORCE_INTERACTIVE:-}" == "1" ]] && return 0
    [[ "${HOOKCHECK_FORCE_NONINTERACTIVE:-}" == "1" ]] && return 1
    [[ -t 0 ]]
}

# Read a single y/N answer from the controlling terminal (NOT inherited stdin,
# mirroring the spec-003 --on-drift precedent). The prompt SINK and the answer
# SOURCE are separate so a file-backed test override is not truncated by the
# prompt write: HOOKCHECK_TTY overrides the sink, HOOKCHECK_TTY_IN the source.
# In production both default to /dev/tty (a tty cannot be truncated).
hookcheck::_read_consent() {
    local n="$1"
    local tty_out="${HOOKCHECK_TTY:-/dev/tty}"
    local tty_in="${HOOKCHECK_TTY_IN:-${HOOKCHECK_TTY:-/dev/tty}}"
    local reply=""
    printf 'Re-register %s missing auto-sync hook(s) now? [y/N] ' "$n" >"$tty_out" 2>/dev/null || true
    IFS= read -r reply <"$tty_in" 2>/dev/null || reply=""
    printf '%s' "$reply"
}

# Source install.sh (guarded) only if its writer is not already present — a test
# may pre-define a stub install::register_after_hooks to avoid the heavy source.
hookcheck::_ensure_install_sourced() {
    [[ -n "${_HOOKCHECK_INSTALL_SOURCED:-}" ]] && return 0
    if ! declare -F install::register_after_hooks >/dev/null 2>&1; then
        # shellcheck source=./install.sh disable=SC1091
        source "${HOOKCHECK_SCRIPT_DIR}/install.sh"
    fi
    _HOOKCHECK_INSTALL_SOURCED=1
}

# -----------------------------------------------------------------------------
# hookcheck::offer_selfheal <overall> <missing...>
# Interactive consented re-registration. The ONLY mutating function.
# -----------------------------------------------------------------------------
hookcheck::offer_selfheal() {
    local overall="$1"; shift
    local -a missing=("$@")

    case "$overall" in
        partial|none) ;;
        *) return 0 ;;   # nothing missing → no offer
    esac

    hookcheck::_is_interactive || return 0   # non-interactive → warn-only

    local reply
    reply="$(hookcheck::_read_consent "${#missing[@]}")"
    case "$reply" in
        y|Y|yes|YES|Yes)
            hookcheck::_ensure_install_sourced
            install::register_after_hooks
            summary::add updated \
                "re-registered ${#missing[@]} auto-sync hook(s): ${missing[*]}"
            # Re-assess so a follow-up reconcile reports clean (SC-004).
            hookcheck::assess_into
            ;;
        *)
            : # decline → no-op; the standing warning remains
            ;;
    esac
}

# -----------------------------------------------------------------------------
# hookcheck::reconcile_check — once-per-run entrypoint for reconcile::main.
# No stdout; effects land in the structured summary (and, on consent, the file).
# -----------------------------------------------------------------------------
hookcheck::reconcile_check() {
    hookcheck::assess_into
    hookcheck::warn_once "$HOOKCHECK_OVERALL" "${HOOKCHECK_MISSING[@]}"
    hookcheck::offer_selfheal "$HOOKCHECK_OVERALL" "${HOOKCHECK_MISSING[@]}"
}
