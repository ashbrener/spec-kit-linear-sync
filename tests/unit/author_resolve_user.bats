#!/usr/bin/env bats
# tests/unit/author_resolve_user.bats — 010 author→Linear-user resolution
# and handle derivation. The workspace `users` roster is stubbed (no real
# Linear). Covers override-first, roster case-insensitive match, inactive
# skip, non-member empty, pagination, and the non-PII handle (SC-006).

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
RECONCILE_SH="${SRC_ROOT}/src/reconcile.sh"

# Run a snippet with reconcile.sh sourced and graphql::query stubbed to
# emit the given JSON (single page). Extra setup lines run before the call.
run_resolver() {  # <stub-json> <snippet>
    local stub="$1" snippet="$2"
    run bash -c "
        source '${RECONCILE_SH}' 2>/dev/null || true
        graphql::query() { cat <<'JSON'
${stub}
JSON
        }
        ${snippet}
    "
}

@test "_author_handle: email local-part, lowercased, no @domain (SC-006)" {
    run_resolver '{}' "reconcile::_author_handle 'Alice.Smith@corp.example'"
    [ "$output" = "alice.smith" ]
}

@test "_author_handle: bare handle passes through sanitised" {
    run_resolver '{}' "reconcile::_author_handle 'Bob'"
    [ "$output" = "bob" ]
}

@test "_author_handle: never emits an @ or full email" {
    run_resolver '{}' "for e in a+b@x.io 'weird name@y.com' UP@Q.COM; do reconcile::_author_handle \"\$e\"; echo; done"
    [[ "$output" != *"@"* ]]
}

@test "_resolve_author_user: roster match (case-insensitive), active member" {
    local json='{"data":{"users":{"nodes":[{"id":"U-1","email":"Alice@Example.com","active":true}],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}'
    run_resolver "$json" "reconcile::_resolve_author_user 'alice@example.com'"
    [ "$output" = "U-1" ]
}

@test "_resolve_author_user: inactive member is skipped (unassigned)" {
    local json='{"data":{"users":{"nodes":[{"id":"U-2","email":"gone@example.com","active":false}],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}'
    run_resolver "$json" "reconcile::_resolve_author_user 'gone@example.com'"
    [ -z "$output" ]
}

@test "_resolve_author_user: non-member → empty" {
    local json='{"data":{"users":{"nodes":[{"id":"U-3","email":"someone@example.com","active":true}],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}'
    run_resolver "$json" "reconcile::_resolve_author_user 'ghost@example.com'"
    [ -z "$output" ]
}

@test "_resolve_author_user: override-first wins over roster" {
    local json='{"data":{"users":{"nodes":[{"id":"ROSTER","email":"alice@example.com","active":true}],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}'
    run_resolver "$json" "
        CONFIG_AUTHORS_USER_ID['alice@example.com']='OVERRIDE-9'
        reconcile::_resolve_author_user 'alice@example.com'
    "
    [ "$output" = "OVERRIDE-9" ]
}

@test "_resolve_author_user: override null → non-member (empty), no roster fallthrough" {
    local json='{"data":{"users":{"nodes":[{"id":"ROSTER","email":"c@example.com","active":true}],"pageInfo":{"hasNextPage":false,"endCursor":""}}}}'
    run_resolver "$json" "
        CONFIG_AUTHORS_USER_ID['c@example.com']='null'
        reconcile::_resolve_author_user 'c@example.com'
    "
    [ -z "$output" ]
}

@test "_resolve_author_user: bare handle with no override and no @ → empty" {
    run_resolver '{}' "reconcile::_resolve_author_user 'bob'"
    [ -z "$output" ]
}
