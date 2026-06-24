#!/usr/bin/env bats
# shellcheck shell=bats
# =============================================================================
# tests/unit/hookcheck.bats — 014 hook-health detection (FR-001..FR-008).
#
# Covers hookcheck::classify (present/disabled/absent), hookcheck::assess
# (overall + missing + disabled, incl. malformed/not_installed), the status
# line render, and the FR-007/R6 pin that HOOKCHECK_AFTER_HOOK_NAMES matches
# install's INSTALL_AFTER_HOOK_NAMES.
# =============================================================================

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
HOOKCHECK_SH="${SRC_ROOT}/src/hookcheck.sh"
INSTALL_SH="${SRC_ROOT}/src/install.sh"

setup() {
    load '../helpers/hookcheck_fixtures'
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-hookcheck-XXXXXX")"
    YML="${TEST_TMP}/extensions.yml"
}

teardown() {
    [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"
}

_classify() {  # <hook> <yml>
    run bash -c "source '${HOOKCHECK_SH}'; hookcheck::classify '$1' '$2'"
}

_assess() {  # <yml>
    run bash -c "source '${HOOKCHECK_SH}'; hookcheck::assess '$1'"
}

# ---- classify ---------------------------------------------------------------

@test "classify: a registered enabled linear hook → present" {
    hookcheck_fixtures::all_present "$YML"
    _classify after_specify "$YML"
    [ "$status" -eq 0 ]
    [ "$output" = "present" ]
}

@test "classify: an enabled:false linear hook → disabled (not missing)" {
    hookcheck_fixtures::one_disabled "$YML"
    _classify after_specify "$YML"
    [ "$output" = "disabled" ]
}

@test "classify: a hook with no linear entry → absent" {
    hookcheck_fixtures::partial "$YML"     # only specify/clarify/plan present
    _classify after_tasks "$YML"
    [ "$output" = "absent" ]
}

@test "classify: a git sibling's enabled:false does NOT make linear disabled" {
    hookcheck_fixtures::git_sibling_disabled "$YML"
    _classify after_specify "$YML"
    [ "$output" = "present" ]
}

@test "classify: a git-only block → linear absent for that hook" {
    hookcheck_fixtures::none "$YML"
    _classify after_plan "$YML"
    [ "$output" = "absent" ]
}

# ---- assess -----------------------------------------------------------------

@test "assess: all six present → overall=present, no missing" {
    hookcheck_fixtures::all_present "$YML"
    _assess "$YML"
    [[ "$output" == *"overall=present"* ]]
    [[ "$output" == *"missing="$'\n'* || "$output" == *"missing="* ]]
    # missing line must be empty
    run bash -c "source '${HOOKCHECK_SH}'; hookcheck::assess '$YML' | sed -n 's/^missing=//p'"
    [ -z "$output" ]
}

@test "assess: three present three absent → overall=partial naming the absent" {
    hookcheck_fixtures::partial "$YML"
    run bash -c "source '${HOOKCHECK_SH}'; hookcheck::assess '$YML'"
    [[ "$output" == *"overall=partial"* ]]
    [[ "$output" == *"after_tasks"* ]]
    [[ "$output" == *"after_implement"* ]]
    [[ "$output" == *"after_analyze"* ]]
}

@test "assess: no linear hooks at all → overall=none" {
    hookcheck_fixtures::none "$YML"
    _assess "$YML"
    [[ "$output" == *"overall=none"* ]]
}

@test "assess: a disabled hook is not missing → overall=present, listed disabled" {
    hookcheck_fixtures::one_disabled "$YML"
    run bash -c "source '${HOOKCHECK_SH}'; hookcheck::assess '$YML'"
    [[ "$output" == *"overall=present"* ]]
    [[ "$output" == *"disabled=after_specify"* ]]
}

@test "assess: readable but no hooks: key → overall=unverifiable (not none)" {
    hookcheck_fixtures::malformed "$YML"
    _assess "$YML"
    [[ "$output" == *"overall=unverifiable"* ]]
}

@test "assess: absent file → overall=not_installed" {
    _assess "${TEST_TMP}/does-not-exist.yml"
    [[ "$output" == *"overall=not_installed"* ]]
}

@test "assess: always exits 0 (non-blocking) even when unverifiable" {
    hookcheck_fixtures::malformed "$YML"
    _assess "$YML"
    [ "$status" -eq 0 ]
}

# ---- status line ------------------------------------------------------------

@test "status_line: partial names the missing hooks + remediation" {
    run bash -c "source '${HOOKCHECK_SH}'; hookcheck::status_line partial after_tasks after_implement --"
    [[ "$output" == *"partial"* ]]
    [[ "$output" == *"after_tasks"* ]]
    [[ "$output" == *"/speckit.linear.install"* ]]
}

@test "status_line: none → none registered + remediation" {
    run bash -c "source '${HOOKCHECK_SH}'; hookcheck::status_line none --"
    [[ "$output" == *"none registered"* ]]
    [[ "$output" == *"/speckit.linear.install"* ]]
}

@test "status_line: present → all present" {
    run bash -c "source '${HOOKCHECK_SH}'; hookcheck::status_line present --"
    [[ "$output" == *"all present"* ]]
}

# ---- FR-007 / R6 pin --------------------------------------------------------

@test "HOOKCHECK_AFTER_HOOK_NAMES is identical to install's INSTALL_AFTER_HOOK_NAMES" {
    run bash -c "
        source '${HOOKCHECK_SH}'
        source '${INSTALL_SH}'
        printf '%s\n' \"\${HOOKCHECK_AFTER_HOOK_NAMES[*]}\"
        printf '%s\n' \"\${INSTALL_AFTER_HOOK_NAMES[*]}\"
    "
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "${lines[1]}" ]
    [ -n "${lines[0]}" ]
}
