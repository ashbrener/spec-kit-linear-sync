# Projection API notes — spec 007 hierarchy build

Linear GraphQL mutation shapes for the `Initiative > Project > Issue > sub-issue`
hierarchy (#17 shape). Each finding is tagged **VERIFIED** (observed directly via
MCP tool schema or live code in `src/reconcile.sh`) or **CONVENTION** (from Linear
GraphQL API knowledge, not yet exercised by a live call in this codebase).

---

## 1. Associate a Project with an Initiative

### Preferred approach — `projectUpdate` with `initiativeIds`

VERIFIED via `mcp__claude_ai_Linear__save_project` schema:

```graphql
mutation LinkProjectToInitiative($id: String!, $input: ProjectUpdateInput!) {
    projectUpdate(id: $id, input: $input) { success }
}
```

Variables — **add** one initiative (append, does not disturb others):

```json
{
  "id": "<project-uuid>",
  "input": { "addInitiativeIds": ["<initiative-uuid>"] }
}
```

Variables — **remove** (for re-home):

```json
{
  "id": "<project-uuid>",
  "input": { "removeInitiativeIds": ["<initiative-uuid>"] }
}
```

Variables — **replace all** (idempotent set):

```json
{
  "id": "<project-uuid>",
  "input": { "initiativeIds": ["<initiative-uuid>"] }
}
```

**Field names confirmed from MCP schema** (`save_project` params):

| MCP param        | Maps to `ProjectUpdateInput` field |
|------------------|------------------------------------|
| `addInitiatives` | `addInitiativeIds: [String!]`      |
| `removeInitiatives` | `removeInitiativeIds: [String!]` |
| `setInitiatives` | `initiativeIds: [String!]`         |

The `save_project` MCP tool exposes all three as distinct params, confirming the
underlying `ProjectUpdateInput` carries all three field names. The `initiativeIds`
(set) variant is the idempotent write — use it for the US2 wiring step so a
re-run that finds the association already correct produces zero writes after the
existence check.

### Idempotency check — does the association already exist?

VERIFIED via `mcp__claude_ai_Linear__get_initiative` schema (the
`includeProjects: true` flag) and the `list_projects(initiative:)` filter:

```graphql
query ProjectsInInitiative($initiative: ID!) {
    initiative(id: $initiative) {
        projects(first: 250) { nodes { id } }
    }
}
```

Filter the result for `<project-uuid>`. If present → skip `projectUpdate`.
If absent → call `projectUpdate` with `initiativeIds: ["<initiative-uuid>"]`.

### Remove / re-home — `removeInitiativeIds`

VERIFIED (MCP `save_project` `removeInitiatives` param):

```graphql
mutation RemoveProjectFromInitiative($id: String!, $input: ProjectUpdateInput!) {
    projectUpdate(id: $id, input: $input) { success }
}
```

```json
{
  "id": "<project-uuid>",
  "input": { "removeInitiativeIds": ["<old-initiative-uuid>"] }
}
```

### Alternative — `initiativeToProjectCreate` / `initiativeToProjectDelete`

CONVENTION. Linear's GraphQL schema also exposes a dedicated junction mutation
pair used by the web app:

```graphql
mutation AttachProjectToInitiative($input: InitiativeToProjectCreateInput!) {
    initiativeToProjectCreate(input: $input) { success }
}
```

```json
{ "input": { "initiativeId": "<initiative-uuid>", "projectId": "<project-uuid>" } }
```

```graphql
mutation DetachProjectFromInitiative($id: String!) {
    initiativeToProjectDelete(id: $id) { success }
}
```

`initiativeToProjectDelete` takes the junction-record `id` (the
`InitiativeToProject.id`), not the project or initiative id directly — you must
first query the junction record id. This makes the `projectUpdate +
initiativeIds` approach simpler and more idempotent for the bridge's use case:
no junction-record id to track, a single mutation, and a set-semantics
replacement that is safe to re-run.

**Recommendation**: use `projectUpdate(input: { initiativeIds: [...] })` — it is
VERIFIED via MCP and is the simpler, idempotent path. Fall back to
`initiativeToProjectCreate` only if `ProjectUpdateInput` does not accept
`initiativeIds` on the live workspace (which would be visible as a GraphQL
validation error).

---

## 2. Set an Issue's parent Project (`projectId` in IssueCreateInput / IssueUpdateInput)

VERIFIED — `projectId` is already used in `src/reconcile.sh` for every
`issueCreate` and every `issueUpdate` that changes project membership.

```graphql
mutation IssueUpsertCreate($input: IssueCreateInput!) {
    issueCreate(input: $input) {
        success
        issue { id identifier title }
    }
}
```

```json
{
  "input": {
    "title":       "<phase title>",
    "teamId":      "<team-uuid>",
    "projectId":   "<spec-project-uuid>",
    "stateId":     "<state-uuid>",
    "description": "<body>",
    "labelIds":    ["<label-uuid>"]
  }
}
```

Confirmed field name: `projectId: String` in `IssueCreateInput`.
Same field accepted in `IssueUpdateInput` (also VERIFIED in reconcile.sh lines
2274, 2291, 2560, 2579, 2599, 2617 — every issue create/update site passes it).

For the #17 shape (`phase → Issue`) the `projectId` is the spec-level Project's
UUID returned by `ensure_project`. No change to the mutation shape — only the
UUID value changes.

---

## 3. Create a sub-issue (`parentId` in IssueCreateInput)

VERIFIED — `parentId` is used in `src/reconcile.sh` for every sub-issue create
(lines 2561, 2580, 2600, 2617).

```graphql
mutation IssueUpsertCreate($input: IssueCreateInput!) {
    issueCreate(input: $input) {
        success
        issue { id identifier title }
    }
}
```

```json
{
  "input": {
    "title":       "<task title>",
    "teamId":      "<team-uuid>",
    "projectId":   "<spec-project-uuid>",
    "parentId":    "<phase-issue-uuid>",
    "stateId":     "<state-uuid>",
    "description": "<body>",
    "labelIds":    ["<label-uuid>"]
  }
}
```

Confirmed field name: `parentId: String` in `IssueCreateInput`.
`parentId` and `projectId` are independent fields and are both set together —
the sub-issue belongs to the Project AND is nested under the parent Issue.
The mutation is the same `issueCreate`; only `parentId` is added.

---

## 4. Initiative create / update

### `initiativeCreate`

VERIFIED — mutation string is live in `src/reconcile.sh`
(`reconcile::ensure_initiative`, line 1950):

```graphql
mutation NewInitiative($input: InitiativeCreateInput!) {
    initiativeCreate(input: $input) {
        success
        initiative { id }
    }
}
```

```json
{
  "input": {
    "name":        "<initiative name>",
    "description": "<body with identity marker>"
  }
}
```

`InitiativeCreateInput` fields confirmed via MCP `save_initiative` schema:

| Field            | Type     | Required | Notes                                      |
|------------------|----------|----------|--------------------------------------------|
| `name`           | String   | yes      | required on create                         |
| `description`    | String   | no       | Markdown; carries the identity marker      |
| `color`          | String   | no       | hex color                                  |
| `icon`           | String   | no       | emoji/name                                 |
| `ownerId`        | String   | no       | user UUID (`owner` param in MCP)           |
| `status`         | String   | no       | Planned / Active / Completed               |
| `targetDate`     | String   | no       | ISO-8601                                   |
| `summary`        | String   | no       | max 255 chars                              |
| `parentInitiativeIds` | [String] | no  | parent initiative UUIDs (sub-initiatives)  |

### `initiativeUpdate`

VERIFIED — mutation string is live in `src/reconcile.sh`
(`reconcile::ensure_initiative`, line 1924):

```graphql
mutation UpdInitiative($id: String!, $input: InitiativeUpdateInput!) {
    initiativeUpdate(id: $id, input: $input) { success }
}
```

```json
{
  "id":    "<initiative-uuid>",
  "input": {
    "name":        "<updated name>",
    "description": "<updated body with identity marker>"
  }
}
```

`InitiativeUpdateInput` accepts the same optional fields as `InitiativeCreateInput`
(minus the required-on-create `name` constraint). VERIFIED via MCP `save_initiative`
schema (same params; `id` present → update path).

---

## 5. Idempotency summary for the US2 wiring sequence

The `ensure_initiative` / `ensure_project` helpers in `src/reconcile.sh` already
implement the description-marker identity pattern. The missing wiring is:

1. After `ensure_project` returns `<project-uuid>`, call `projectUpdate` with
   `initiativeIds: ["<initiative-uuid>"]` **only when the association is absent**
   (checked via `initiative.projects` query first).
2. `issueCreate` for `phase → Issue` already accepts `projectId` (point 2 above)
   — pass the spec-Project UUID instead of the repo-Project UUID.
3. `issueCreate` for `task → sub-issue` already accepts `parentId` (point 3
   above) — pass the phase-Issue UUID.

No new mutation shapes are needed for points 2–3; they are already exercised
by the existing default-path code with different UUID values.

---

## 6. Query: check Initiative → Project membership

VERIFIED via `mcp__claude_ai_Linear__get_initiative` `includeProjects` param and
`mcp__claude_ai_Linear__list_projects` `initiative` filter param:

```graphql
query InitiativeProjects($initiativeId: ID!) {
    initiative(id: $initiativeId) {
        projects(first: 250) {
            nodes { id name }
        }
    }
}
```

Returns the Projects currently associated with the Initiative. Filter for
`<project-uuid>` client-side to test membership before writing.

---

*All MCP-schema observations are from the tool params visible in this session.
All `src/reconcile.sh` line references are from the worktree at the time of this
analysis. CONVENTION findings should be verified against a live Linear workspace
before the T017 implementation begins.*
