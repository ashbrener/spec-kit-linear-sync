#!/usr/bin/env bats
# tests/integration/author-attribution.bats — 010 end-to-end author
# resolution + projection composition over a real two-author git fixture
# with a stubbed Linear `users` roster. Gated by RUN_INTEGRATION_TESTS=1
# (does not run in CI; complements the unit suite's per-function coverage by
# locking the full per-spec decision: git author → roster → label + assignee).

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
load "${SRC_ROOT}/tests/helpers/integration-helpers.bash"
RECONCILE_SH="${SRC_ROOT}/src/reconcile.sh"

setup() {
    integration::skip_unless_enabled
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-author-e2e-XXXXXX")"
}
teardown() {
    [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"
}

# Build a repo where spec 010 was first added by a member (alice) and spec
# 011 by a non-member (bob), then resolve+project both with a stubbed roster
# that knows only alice. Asserts: alice → label author:alice + assignee U-1;
# bob → label author:bob + UNASSIGNED.
@test "two-author repo: member assigned+labelled, non-member labelled+unassigned" {
    run bash -c "
        set -e
        cd '${TEST_TMP}'
        git init -q && git config user.name CI
        mkdir -p specs/010-a specs/011-b
        printf '# Spec\n' > specs/010-a/spec.md
        printf '# Spec\n' > specs/011-b/spec.md
        git config user.email 'alice@example.com'; git add specs/010-a; git commit -qm a
        git config user.email 'bob@example.com';   git add specs/011-b; git commit -qm b

        source '${RECONCILE_SH}' 2>/dev/null || true
        # Stub the roster: only alice is an active member.
        graphql::query() { cat <<'JSON'
{\"data\":{\"users\":{\"nodes\":[{\"id\":\"U-1\",\"email\":\"alice@example.com\",\"active\":true}],\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":\"\"}}}}
JSON
        }
        for s in 010-a 011-b; do
            ar=\"\$(parser::resolve_author \"specs/\$s\" \"specs/\$s/spec.md\")\"
            id=\"\${ar%%\$'\t'*}\"
            handle=\"\$(reconcile::_author_handle \"\$id\")\"
            assignee=\"\$(reconcile::_resolve_author_user \"\$id\")\"
            printf '%s label=author:%s assignee=[%s]\n' \"\$s\" \"\$handle\" \"\$assignee\"
        done
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"010-a label=author:alice assignee=[U-1]"* ]]
    [[ "$output" == *"011-b label=author:bob assignee=[]"* ]]
}
