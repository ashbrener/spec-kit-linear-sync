#!/usr/bin/env bats
# tests/unit/author_parser.bats — 010 author resolution from the filesystem.
#
# Covers parser::spec_owner_line, parser::spec_git_first_author, and the
# composite parser::resolve_author (owner > git > unknown; Name <email>
# normalization — analyze U1). Pure parser layer; no Linear, no config.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
PARSER_SH="${SRC_ROOT}/src/parser.sh"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-author-XXXXXX")"
}
teardown() {
    [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"
}

write_spec() {  # <relpath> <owner-line-or-empty>
    local dir="${TEST_TMP}/$1"
    mkdir -p "$dir"
    {
        printf '# Feature Specification: X\n\n'
        printf '**Feature Branch**: `010-x`\n\n'
        [[ -n "$2" ]] && printf '%s\n' "$2"
        printf '**Status**: Draft\n'
    } > "${dir}/spec.md"
    printf '%s' "$dir"
}

@test "spec_owner_line: **Owner:** colon-inside extracts the value" {
    d="$(write_spec specs/010-x '**Owner:** alice@example.com')"
    run bash -c "source '${PARSER_SH}'; parser::spec_owner_line '${d}/spec.md'"
    [ "$status" -eq 0 ]
    [ "$output" = "alice@example.com" ]
}

@test "spec_owner_line: **Author**: colon-outside extracts the value" {
    d="$(write_spec specs/010-x '**Author**: bob')"
    run bash -c "source '${PARSER_SH}'; parser::spec_owner_line '${d}/spec.md'"
    [ "$output" = "bob" ]
}

@test "spec_owner_line: tolerates a leading list marker" {
    d="$(write_spec specs/010-x '- **Owner:** carol@x.io')"
    run bash -c "source '${PARSER_SH}'; parser::spec_owner_line '${d}/spec.md'"
    [ "$output" = "carol@x.io" ]
}

@test "spec_owner_line: absent owner line → empty" {
    d="$(write_spec specs/010-x '')"
    run bash -c "source '${PARSER_SH}'; parser::spec_owner_line '${d}/spec.md'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "resolve_author: owner line wins and Name <email> normalizes to bare email" {
    d="$(write_spec specs/010-x '**Owner:** Alice Smith <alice@example.com>')"
    run bash -c "source '${PARSER_SH}'; parser::resolve_author '${d}' '${d}/spec.md'"
    [ "$output" = "$(printf 'alice@example.com\towner_line')" ]
}

@test "resolve_author: git first-add fallback when no owner line" {
    d="$(write_spec specs/010-x '')"
    run bash -c "
        cd '${TEST_TMP}'
        git init -q && git config user.email 'first@example.com' && git config user.name 'First'
        git add -A && git commit -qm 'add spec'
        git config user.email 'later@example.com'
        printf 'more\n' >> specs/010-x/spec.md && git add -A && git commit -qm 'edit'
        source '${PARSER_SH}'
        parser::resolve_author 'specs/010-x' 'specs/010-x/spec.md'
    "
    [ "$output" = "$(printf 'first@example.com\tgit_first_add')" ]
}

@test "resolve_author: neither source resolves → unknown (empty identity)" {
    d="$(write_spec specs/010-x '')"
    run bash -c "source '${PARSER_SH}'; parser::resolve_author '${d}' '${d}/spec.md'"
    # No git history (TEST_TMP is not a repo), no owner line → \tunknown.
    [ "$output" = "$(printf '\tunknown')" ]
}

@test "spec_git_first_author: non-repo / untracked dir → empty (graceful)" {
    d="$(write_spec specs/010-x '')"
    run bash -c "source '${PARSER_SH}'; parser::spec_git_first_author '${d}'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
