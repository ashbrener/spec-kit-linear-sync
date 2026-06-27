#!/usr/bin/env bats
# shellcheck shell=bats
# =============================================================================
# tests/unit/hookcheck_selfheal.bats — 014 warn-once latch (FR-010) +
# consented self-heal (FR-009).
#
# Self-heal is INTERACTIVE + CONSENTED only: interactive `y` re-registers all
# missing hooks at once via install's writer; `n`/empty declines; a non-
# interactive run never prompts and never mutates. Tests stub summary::add and
# install::register_after_hooks so no real Linear/install machinery runs.
# =============================================================================

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
HOOKCHECK_SH="${SRC_ROOT}/src/hookcheck.sh"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-selfheal-XXXXXX")"
    OUT="${TEST_TMP}/calls.log"
    ANS="${TEST_TMP}/answer"
    : >"$OUT"
    # Keep assess_into (called by reconcile_check / post-heal re-assess) off any
    # real file.
    NO_YML="${TEST_TMP}/none.yml"
}

teardown() {
    [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"
}

# Shared preamble: source the module then install stubs that record calls.
_preamble() {
    cat <<EOF
source '${HOOKCHECK_SH}'
summary::add() { printf 'SUMMARY:%s:%s\n' "\$1" "\$2" >>'${OUT}'; }
install::register_after_hooks() { printf 'REGISTERED\n' >>'${OUT}'; }
export HOOKCHECK_EXTENSIONS_YML='${NO_YML}'
EOF
}

# ---- warn_once latch --------------------------------------------------------

@test "warn_once: emits a named warning once for partial" {
    run bash -c "$(_preamble)
        declare -g _RECONCILE_HOOKS_WARNED=0
        hookcheck::warn_once partial after_tasks after_implement
        cat '${OUT}'"
    [[ "$output" == *"SUMMARY:warned:"* ]]
    [[ "$output" == *"after_tasks"* ]]
    [[ "$output" == *"/speckit.linear.install"* ]]
}

@test "warn_once: latched — second call in the same run is silent" {
    run bash -c "$(_preamble)
        declare -g _RECONCILE_HOOKS_WARNED=0
        hookcheck::warn_once none after_specify after_clarify after_plan after_tasks after_implement after_analyze
        hookcheck::warn_once none after_specify after_clarify after_plan after_tasks after_implement after_analyze
        grep -c 'SUMMARY:warned' '${OUT}' || true"
    [ "$output" = "1" ]
}

@test "warn_once: present emits nothing" {
    run bash -c "$(_preamble)
        declare -g _RECONCILE_HOOKS_WARNED=0
        hookcheck::warn_once present
        wc -l <'${OUT}' | tr -d ' '"
    [ "$output" = "0" ]
}

@test "warn_once: unverifiable emits one info row, not a warning" {
    run bash -c "$(_preamble)
        declare -g _RECONCILE_HOOKS_WARNED=0
        hookcheck::warn_once unverifiable
        cat '${OUT}'"
    [[ "$output" == *"SUMMARY:info:"* ]]
    [[ "$output" != *"SUMMARY:warned"* ]]
}

# ---- offer_selfheal ---------------------------------------------------------

@test "offer_selfheal: interactive 'y' re-registers all missing at once" {
    printf 'y\n' >"$ANS"
    run bash -c "$(_preamble)
        export HOOKCHECK_FORCE_INTERACTIVE=1 HOOKCHECK_TTY=/dev/null HOOKCHECK_TTY_IN='${ANS}'
        export _HOOKCHECK_INSTALL_SOURCED=1
        hookcheck::offer_selfheal partial after_tasks after_implement after_analyze
        cat '${OUT}'"
    [[ "$output" == *"REGISTERED"* ]]
    [[ "$output" == *"SUMMARY:updated:"* ]]
    # ONE registration call (all-at-once), not one per hook.
    run bash -c "grep -c REGISTERED '${OUT}' || true"
    [ "$output" = "1" ]
}

@test "offer_selfheal: interactive 'n' declines — no registration" {
    printf 'n\n' >"$ANS"
    run bash -c "$(_preamble)
        export HOOKCHECK_FORCE_INTERACTIVE=1 HOOKCHECK_TTY=/dev/null HOOKCHECK_TTY_IN='${ANS}'
        export _HOOKCHECK_INSTALL_SOURCED=1
        hookcheck::offer_selfheal partial after_tasks after_implement
        cat '${OUT}'"
    [[ "$output" != *"REGISTERED"* ]]
}

@test "offer_selfheal: interactive empty answer declines (default No)" {
    : >"$ANS"
    run bash -c "$(_preamble)
        export HOOKCHECK_FORCE_INTERACTIVE=1 HOOKCHECK_TTY=/dev/null HOOKCHECK_TTY_IN='${ANS}'
        export _HOOKCHECK_INSTALL_SOURCED=1
        hookcheck::offer_selfheal none after_specify after_clarify after_plan after_tasks after_implement after_analyze
        cat '${OUT}'"
    [[ "$output" != *"REGISTERED"* ]]
}

@test "offer_selfheal: non-interactive never prompts and never mutates" {
    printf 'y\n' >"$ANS"   # even with a 'y' waiting, non-interactive must ignore it
    run bash -c "$(_preamble)
        export HOOKCHECK_FORCE_NONINTERACTIVE=1 HOOKCHECK_TTY=/dev/null HOOKCHECK_TTY_IN='${ANS}'
        export _HOOKCHECK_INSTALL_SOURCED=1
        hookcheck::offer_selfheal partial after_tasks after_implement
        wc -l <'${OUT}' | tr -d ' '"
    [ "$output" = "0" ]
}

@test "offer_selfheal: nothing missing (present) → no offer regardless of tty" {
    printf 'y\n' >"$ANS"
    run bash -c "$(_preamble)
        export HOOKCHECK_FORCE_INTERACTIVE=1 HOOKCHECK_TTY=/dev/null HOOKCHECK_TTY_IN='${ANS}'
        export _HOOKCHECK_INSTALL_SOURCED=1
        hookcheck::offer_selfheal present
        wc -l <'${OUT}' | tr -d ' '"
    [ "$output" = "0" ]
}
