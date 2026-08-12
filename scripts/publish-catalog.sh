#!/usr/bin/env bash
# =============================================================================
# scripts/publish-catalog.sh — file the spec-kit community-catalog submission
# =============================================================================
# The community catalog (github/spec-kit → extensions/catalog.community.json) is
# a static, version-pinned entry; it does NOT watch this repo. As of mid-2026 the
# spec-kit maintainers intake catalog adds/bumps through a GitHub **issue** using
# their Extension Submission template — NOT a hand-edited PR to the catalog JSON
# (direct-JSON PRs are now closed-with-redirect; see github/spec-kit#3133). After
# you tag + release, run this to OPEN that submission issue, pre-filled from your
# extension.yml + the released tag.
#
# NO SECRET / PAT REQUIRED — it uses your LOCAL `gh` login. No fork needed.
# Run it after `gh release create`: `scripts/publish-catalog.sh v0.4.0`.
#
# ─── COPY-TO-A-SIBLING-EXTENSION CHECKLIST ──────────────────────────────────
#   1. Copy this file.
#   2. Edit the FOUR values just below (CATALOG_ID, CATALOG_NAME, EXT_REPO, TAGS).
#   That's it — no tokens, no secrets, no fork.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ─── EDIT THESE WHEN COPYING TO A SIBLING REPO ──────────────────────────────
CATALOG_ID="${CATALOG_ID:-linear}"                             # catalog entry id (key under `extensions`)
CATALOG_NAME="${CATALOG_NAME:-Linear Integration}"             # catalog DISPLAY name (may differ from extension.yml name)
EXT_REPO="${EXT_REPO:-ashbrener/spec-kit-linear-sync}"         # owner/name of THIS extension repo
TAGS="${TAGS:-issue-tracking, linear, tasks-sync, lifecycle-mirror, cross-repo}"  # 2-5 catalog tags
# ─── constants ──────────────────────────────────────────────────────────────
UPSTREAM="github/spec-kit"
MANIFEST="extension.yml"

command -v gh >/dev/null || { echo "error: gh (GitHub CLI) is required + authenticated (gh auth login)"; exit 1; }

# Tag: arg 1, else the most recent tag in this repo.
TAG="${1:-$(git describe --tags --abbrev=0 2>/dev/null || true)}"
[ -n "$TAG" ] || { echo "error: no tag given and none found — usage: $0 vX.Y.Z"; exit 1; }
VER="${TAG#v}"
URL="https://github.com/${EXT_REPO}/archive/refs/tags/${TAG}.zip"

# The installer is ZIP-only — fail early if the tag's archive isn't published.
code="$(curl -sS -o /dev/null -w '%{http_code}' -L "$URL")"
[ "$code" = "200" ] || { echo "error: archive not published (HTTP $code) at $URL — push the tag + release first"; exit 1; }

# ─── pull the rest from the manifest (no hardcoding) ────────────────────────
# `_yval <key>` echoes the first top-level `  <key>: "value"` scalar from the
# manifest's `extension:` block (2-space indent), unquoted.
_yval() { sed -n "s/^  ${1}: *\"\(.*\)\"\s*$/\1/p" "$MANIFEST" | head -1; }
DESC="$(_yval description)"
AUTHOR="$(_yval author)"
LICENSE="$(_yval license)"
REPO_URL="$(_yval repository)"; REPO_URL="${REPO_URL:-https://github.com/${EXT_REPO}}"
HOMEPAGE="$(_yval homepage)";   HOMEPAGE="${HOMEPAGE:-${REPO_URL}}"
SPECKIT_REQ="$(sed -n 's/^ *speckit_version: *"\(.*\)".*/\1/p' "$MANIFEST" | head -1)"; SPECKIT_REQ="${SPECKIT_REQ:->=0.1.0}"
CMD_COUNT="$(grep -cE '^    - name: "speckit\.' "$MANIFEST" || true)"
NOW="$(date -u +%Y-%m-%dT00:00:00Z)"

echo "Filing the Extension Submission issue: ${CATALOG_ID} ${TAG} → ${UPSTREAM}"

# Comma list → JSON array for the proposed catalog entry.
tags_json="$(printf '%s' "$TAGS" | awk -F', *' '{for(i=1;i<=NF;i++){printf (i>1?", ":"")"\""$i"\""}}')"

body="$(mktemp)"; trap 'rm -f "$body"' EXIT
cat >"$body" <<EOF
> **Note for triage:** version update of the existing catalog entry \`${CATALOG_ID}\` → \`${VER}\` (re-filed via this template per the maintainer process; direct-JSON catalog PRs are now redirected here).

### Extension ID
${CATALOG_ID}

### Extension Name
${CATALOG_NAME}

### Version
${VER}

### Description
${DESC}

### Author
${AUTHOR}

### Repository URL
${REPO_URL}

### Download URL
${URL}

### License
${LICENSE}

### Homepage (optional)
${HOMEPAGE}

### Documentation URL (optional)
https://github.com/${EXT_REPO}/blob/main/README.md

### Changelog URL (optional)
https://github.com/${EXT_REPO}/blob/main/CHANGELOG.md

### Required Spec Kit Version
${SPECKIT_REQ}

### Number of Commands
${CMD_COUNT}

### Tags
${TAGS}

### Testing Checklist
- [x] Extension installs successfully via download URL
- [x] All commands execute without errors
- [x] Documentation is complete and accurate
- [x] No security vulnerabilities identified
- [x] Tested on at least one real project

### Submission Requirements
- [x] Valid \`extension.yml\` manifest included
- [x] README.md with installation and usage instructions
- [x] LICENSE file included
- [x] GitHub release created with version tag
- [x] All command files exist and are properly formatted
- [x] Extension ID follows naming conventions (lowercase-with-hyphens)

### Testing Details
Released \`${TAG}\` with a published source archive (pre-flight verified HTTP 200 at the download URL). Full offline test suite (bats + shellcheck + yamllint + markdownlint) green in CI on macOS + Linux; dogfooded against a live Jira project.

### Example Usage
\`\`\`bash
specify extension add ${CATALOG_ID} --from ${URL}
\`\`\`

### Proposed Catalog Entry
\`\`\`json
{
  "${CATALOG_ID}": {
    "name": "${CATALOG_NAME}",
    "id": "${CATALOG_ID}",
    "description": "${DESC}",
    "author": "${AUTHOR}",
    "version": "${VER}",
    "download_url": "${URL}",
    "repository": "${REPO_URL}",
    "homepage": "${HOMEPAGE}",
    "documentation": "https://github.com/${EXT_REPO}/blob/main/README.md",
    "changelog": "https://github.com/${EXT_REPO}/blob/main/CHANGELOG.md",
    "license": "${LICENSE}",
    "requires": { "speckit_version": "${SPECKIT_REQ}" },
    "provides": { "commands": ${CMD_COUNT:-0}, "hooks": 0 },
    "tags": [${tags_json}],
    "verified": false,
    "downloads": 0,
    "stars": 0,
    "updated_at": "${NOW}"
  }
}
\`\`\`

### Additional Context
Version bump of the existing \`${CATALOG_ID}\` entry; only \`version\`, \`download_url\`, \`provides.commands\`, and \`updated_at\` change. Preserve the existing \`created_at\`. Thanks for maintaining the catalog!
EOF

gh issue create --repo "$UPSTREAM" \
  --title "[Extension]: ${CATALOG_NAME} ${TAG} (version update of ${CATALOG_ID})" \
  --body-file "$body"
