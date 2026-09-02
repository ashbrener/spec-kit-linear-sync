#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# src/git_helpers.sh
#
# Git / worktree / PR-state primitives used by the reconciler and by the
# write-authority gate (Principle IV: "Write-Authority Follows The Worktree").
#
# Public functions are namespaced under git_helpers:: and never print to
# stderr unless something has actually gone wrong. They are designed to be
# safe to call repeatedly (idempotent, no side effects) so the reconciler
# can ask the same question from multiple call sites without surprise.
#
# Responsibilities (in spec terms):
#   * Surface the current branch and the worktree → branch map (FR-026)
#   * Implement the write-authority gate for a given spec (FR-025, Principle IV)
#   * Enumerate spec feature branches by their NNN- prefix
#   * Detect a branch's PR state, preferring `gh` when present and falling
#     back to git-only branch-reachability (FR-030)
#   * Produce a cross-platform ISO 8601 mtime for "last touched on disk"
#     surfaces in the spec Issue's memory block (FR-004)
#
# Non-responsibilities: this module does NOT mutate git state (no checkouts,
# no resets, no commits) and does NOT make network calls of its own. The
# only external program it may shell out to is `gh`, and only when `gh` is
# already present and authenticated.
# =============================================================================

set -euo pipefail

# Idempotent include-guard (014) — safe to source twice (e.g. when the
# hook self-heal sources install.sh, which re-sources this lib).
[[ -n "${_GIT_HELPERS_SH_LOADED:-}" ]] && return 0
readonly _GIT_HELPERS_SH_LOADED=1

# ---------------------------------------------------------------------------
# Cache the absolute path to `git` at module-source time. The test harness in
# tests/unit/git_helpers.bats forces the git-only fallback path of pr_state by
# stripping every PATH entry that contains a `gh` binary — on most Linux
# distros (and the CI runner) git and gh both live in /usr/bin, so the strip
# also evicts git from PATH. Resolving git here, BEFORE any test manipulates
# PATH, lets pr_state invoke it via the absolute path and keeps the fallback
# working even when PATH has been narrowed. The shell variable falls back to
# the bare `git` token when resolution fails, so non-test consumers see no
# behavioural change.
# ---------------------------------------------------------------------------
_GIT_HELPERS_GIT_BIN="$(command -v git 2>/dev/null || printf 'git')"

# ---------------------------------------------------------------------------
# git_helpers::current_branch
#
# Echoes the name of the currently checked-out branch, or empty string when
# the working tree is in a detached-HEAD state. Never errors out — callers
# treat empty output as "no branch" and gate accordingly.
#
# Implementation note: `git rev-parse --abbrev-ref HEAD` returns the literal
# string "HEAD" when detached. We translate that to empty so callers don't
# have to special-case the sentinel.
# ---------------------------------------------------------------------------
git_helpers::current_branch() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    return 0
  fi
  printf '%s\n' "$branch"
}

# ---------------------------------------------------------------------------
# git_helpers::list_worktrees
#
# Emits one line per worktree in the form:   <path>\t<branch>
#
# A worktree on a detached HEAD is emitted with an empty branch field
# (i.e. the line ends with a literal trailing tab) so callers can still
# count it without parsing porcelain output.
#
# This wraps `git worktree list --porcelain`, whose record format is:
#   worktree <path>
#   HEAD <sha>
#   branch refs/heads/<name>      (only when not detached)
#   <blank line separating records>
#
# We accumulate path + branch across the record and emit the pair when the
# record terminates (either by a blank line OR end of input — the last
# record has no trailing blank line).
# ---------------------------------------------------------------------------
git_helpers::list_worktrees() {
  local path='' branch='' line
  # The trailing `|| true` on read handles the no-final-newline case so
  # the loop body still runs for the last record.
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == worktree\ * ]]; then
      path="${line#worktree }"
      branch=''
    elif [[ "$line" == branch\ refs/heads/* ]]; then
      branch="${line#branch refs/heads/}"
    elif [[ -z "$line" ]]; then
      if [[ -n "$path" ]]; then
        printf '%s\t%s\n' "$path" "$branch"
        path=''
        branch=''
      fi
    fi
  done < <(git worktree list --porcelain 2>/dev/null)

  # Flush the final record (porcelain output has no trailing blank line).
  if [[ -n "$path" ]]; then
    printf '%s\t%s\n' "$path" "$branch"
  fi
}

# ---------------------------------------------------------------------------
# git_helpers::worktree_for_branch <branch>
#
# Echoes the worktree path that currently has <branch> checked out, or
# empty string if no worktree holds that branch.
#
# Exactly one worktree can hold a given branch at a time (git enforces
# this), so the first match is also the only match.
# ---------------------------------------------------------------------------
git_helpers::worktree_for_branch() {
  local target_branch="${1:-}"
  if [[ -z "$target_branch" ]]; then
    return 0
  fi

  local line path branch
  while IFS=$'\t' read -r path branch; do
    if [[ "$branch" == "$target_branch" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done < <(git_helpers::list_worktrees)

  # No worktree currently holds the branch — emit nothing, succeed.
  # Touch the unused locals so shellcheck doesn't complain when this code
  # path falls through with all-empty bindings.
  : "${line:-}"
}

# ---------------------------------------------------------------------------
# git_helpers::is_authoritative_for_spec <NNN>
#
# Returns 0 (true) iff the current branch matches the spec's authoritative
# feature-branch pattern ^<NNN>-.+$ — i.e. the worktree this is called
# from is the one allowed to WRITE to Linear for that spec.
#
# Implements the gate in spec FR-025 and constitution Principle IV.
# Any worktree on `main`, on an unrelated feature branch, or on detached
# HEAD returns 1 — the reconciler then enters read-only mode for that
# spec per FR-026.
#
# <NNN> is the feature number as it appears on disk (typically three
# digits, but the regex allows any non-zero-padded numeric run for
# future-proofing). A non-numeric or empty argument always returns 1.
# ---------------------------------------------------------------------------
git_helpers::is_authoritative_for_spec() {
  local feature_number="${1:-}"
  if [[ -z "$feature_number" || ! "$feature_number" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  local branch
  branch=$(git_helpers::current_branch)
  if [[ -z "$branch" ]]; then
    return 1
  fi

  # Anchor on the feature-number prefix plus a `-` separator and at least
  # one slug character. Matches "001-foo", "001-foo-bar"; rejects "001",
  # "0010-foo" (different number), and "main".
  if [[ "$branch" =~ ^${feature_number}-.+$ ]]; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# git_helpers::feature_branches
#
# Emits every local branch whose name starts with the canonical spec
# feature-branch pattern: ^[0-9]{3,}-.+$ (three or more leading digits,
# a dash, then a non-empty slug).
#
# Used by the reconciler when it needs to enumerate "which specs has an
# operator started branches for". The three-digit minimum matches the
# canonical `specs/NNN-feature/` layout while still allowing four-digit
# expansion if the project ever exceeds 999 specs.
# ---------------------------------------------------------------------------
git_helpers::feature_branches() {
  local branch
  while IFS= read -r branch; do
    # `git branch --format='%(refname:short)'` returns plain branch names
    # with no leading marker character. Trim defensively in case the git
    # version on the runner ever prepends whitespace.
    branch="${branch#"${branch%%[![:space:]]*}"}"
    branch="${branch%"${branch##*[![:space:]]}"}"
    if [[ "$branch" =~ ^[0-9]{3,}-.+$ ]]; then
      printf '%s\n' "$branch"
    fi
  done < <(git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)
}

# ---------------------------------------------------------------------------
# git_helpers::feature_number_for_branch <branch>
#
# Extracts the leading numeric NNN prefix from a feature branch name.
# Echoes the empty string for any input that doesn't match the canonical
# pattern (e.g. `main`, `release/foo`, a branch with no dash separator).
#
# This is the inverse of git_helpers::is_authoritative_for_spec — callers
# use it to derive "which spec does this branch belong to" without
# committing to a specific zero-padding width.
# ---------------------------------------------------------------------------
git_helpers::feature_number_for_branch() {
  local branch="${1:-}"
  if [[ -z "$branch" ]]; then
    return 0
  fi
  if [[ "$branch" =~ ^([0-9]+)-.+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
}

# ---------------------------------------------------------------------------
# git_helpers::pr_state <branch>
#
# Implements FR-030's two-tier PR detection contract:
#
#   1. If `gh` is in PATH AND the operator is authenticated to GitHub via
#      `gh`, return a rich JSON object describing the PR whose HEAD is
#      <branch> (fields: state, isDraft, mergedAt, url). The reconciler
#      decodes whichever fields it needs; "merged" is derived from
#      `state == "MERGED"` (a non-null `mergedAt` corroborates it).
#
#      We query via `gh pr list --head <branch> --state all` rather than
#      `gh pr view <branch>` for two reasons:
#        (a) `gh pr view` requires <branch> to be the *current* branch or
#            otherwise resolvable from local checkout/upstream context;
#            `gh pr list --head` queries the GitHub API directly for ANY
#            branch name, so detection works when reconciling a spec's
#            feature branch (`NNN-...`) from `main` or any other worktree
#            (FR-013 / FR-030 merge detection from any branch).
#        (b) `gh pr list` returns an empty array (exit 0) when no PR
#            exists, vs `gh pr view` which exits non-zero — cleaner to
#            branch on. We take the first (most-recent) matching PR.
#
#      NOTE: there is intentionally NO `merged` field in the --json set —
#      `merged` is not a valid `gh pr {view,list}` JSON field (it errors
#      `Unknown JSON field: "merged"` and aborts the whole query). The
#      original code requested it, so the gh path ALWAYS failed and fell
#      through to the git fallback below; from `main` (where the feature
#      branch has no local ref) that fallback returns indeterminate, so a
#      merged spec was mis-detected as still implementing. Merge state is
#      now read from `state`/`mergedAt`, the real fields.
#
#   2. Otherwise (no `gh` binary, or `gh auth status` failing) fall back to
#      a git-only branch-reachability probe against the trunk:
#        - indeterminate (empty) when the branch tip is IDENTICAL to the
#          trunk tip. A brand-new spec branch has that shape and must never
#          be reported as merged (#90); so does a fast-forward merge, which
#          consequently also reads indeterminate.
#        - "merged" when the branch tip is a (strict) ancestor of the trunk
#          tip.
#        - "open" otherwise.
#
#      This probe is a HEURISTIC, and a partial one. "Never started" and
#      "fully merged" are the same shape in the commit graph, so it cannot
#      separate them: a branch cut from a stale local trunk carries no
#      commits of its own and still reports `merged`, and a squash- or
#      rebase-merged branch reports `open`. Only the exact-tip case above is
#      resolved. See the (c) block in the body for the full accounting and
#      why closing the rest needs a signal from outside the graph.
#
#      <branch> is resolved from `refs/heads/<branch>`, else whatever
#      gitrevisions makes of the bare name; a branch with no local ref is
#      indeterminate (see #72). `refs/remotes/origin/<branch>` is
#      deliberately not consulted — see (a).
#
#      The trunk is resolved in this order: `origin/main`, `origin/master`,
#      `origin/HEAD` (for repos whose default is neither), then the upstream
#      of HEAD as a last-resort best effort. `origin/HEAD` ranks below the
#      conventional names because git never refreshes it after a remote
#      default-branch rename. A candidate that IS the branch under test (or
#      a remote-tracking ref for it) is skipped: comparing a branch against
#      itself always reports "merged", which is how an in-flight branch on a
#      repo without `origin/main` used to land in Linear as Merged.
#
#      In the fallback path we have no signal on draft state or even on
#      "does a PR exist at all" — git alone cannot answer those questions.
#      We emit the bare word `merged` or `open` so the reconciler can still
#      branch on the most operationally important distinction (has the
#      change landed yet?) without conflating it with the richer JSON form.
#      Downstream, `merged` is the only positive signal this path can
#      produce — reconcile::pr_state_hint maps the bare `open` to the empty
#      hint, so `open` and indeterminate both defer to the artifact ladder.
#
# Empty stdout (and exit 0) means "could not determine": no `gh`, no usable
# trunk ref, no local ref for the branch, or the tip-equality case in (c).
# Callers treat it as "no PR signal" and fall through to the artifact
# ladder; note that no caller currently WARNS on it, so an indeterminate
# answer is silent (reconcile::pr_state_hint -> empty hint).
# ---------------------------------------------------------------------------
git_helpers::pr_state() {
  local branch="${1:-}"
  if [[ -z "$branch" ]]; then
    return 0
  fi

  # ----- Path 1: gh CLI is present and authenticated --------------------
  # `command -v gh` returns success iff gh is on PATH. `gh auth status`
  # is the canonical "are we logged in" check; we redirect its noisy
  # output to /dev/null and rely solely on its exit code.
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    local rich first
    # `gh pr list --head <branch> --state all` queries the GitHub API for
    # the PR(s) whose head ref is <branch>, independent of which branch is
    # checked out locally — this is what makes merge detection work when
    # reconciling spec NNN from `main`. Returns a JSON array (possibly
    # empty). We extract the first element (most-recent PR) as the rich
    # object the reconciler expects. Only the valid fields are requested
    # (no `merged` — that field does not exist and would abort the query).
    if rich=$(gh pr list --head "$branch" --state all \
        --json state,isDraft,mergedAt,url 2>/dev/null); then
      if [[ -n "$rich" ]]; then
        # `jq -e .[0]` exits non-zero (and prints nothing usable) when the
        # array is empty, so a no-PR branch falls through to the git probe.
        if first=$(printf '%s' "$rich" | jq -ce '.[0]' 2>/dev/null) \
            && [[ -n "$first" && "$first" != "null" ]]; then
          printf '%s\n' "$first"
          return 0
        fi
      fi
    fi
    # No PR found for this branch (empty array or query failed). Fall
    # through to the git-only probe so we still answer the merged-or-not
    # question that callers actually care about.
  fi

  # ----- Path 2: git-only branch-reachability fallback ------------------
  # NOTE: we invoke git via the absolute path captured at module-source
  # time (see _GIT_HELPERS_GIT_BIN above) so the fallback works even when
  # the test harness has stripped /usr/bin from PATH to evict the `gh`
  # binary alongside it.
  local git_bin="${_GIT_HELPERS_GIT_BIN:-git}"

  # (a) Resolve <branch> to a concrete commit — the local ref first, then
  #     whatever gitrevisions makes of the bare name. Resolving to a SHA up
  #     front keeps the comparisons below from being skewed by an ambiguous
  #     short name.
  #
  #     Deliberately NOT consulted: `refs/remotes/origin/<branch>`. It would
  #     let us answer for a branch pruned locally (one strand of #72), but it
  #     also makes the false-`merged` family in (c) reachable for a pushed
  #     branch carrying no commits of its own — a routine state, since you
  #     push a fresh branch to open the PR. Recovering #72's signal needs the
  #     never-started/merged distinction solved first.
  local branch_sha='' candidate
  for candidate in "refs/heads/$branch" "$branch"; do
    branch_sha=$("$git_bin" rev-parse --verify --quiet "${candidate}^{commit}" 2>/dev/null || printf '')
    if [[ -n "$branch_sha" ]]; then
      break
    fi
  done
  if [[ -z "$branch_sha" ]]; then
    # No such ref locally — we cannot answer. Caller treats empty as
    # "indeterminate" and falls back to the artifact ladder (#72 covers the
    # merge signals this loses).
    return 0
  fi

  # (b) Resolve the trunk we measure the branch against. The conventional
  #     remote names come FIRST: `origin/HEAD` looks more authoritative (it
  #     is the remote's own declaration of its default branch) but git never
  #     refreshes it after a remote default-branch rename, so a master-era
  #     clone can carry `origin/HEAD -> origin/master` alongside a live
  #     `origin/main` indefinitely — trusting it there loses real merges.
  #     It earns its place last, for repos whose default is neither `main`
  #     nor `master`, ahead of the upstream of HEAD as a final best effort.
  #
  #     A candidate that IS the branch under test (its local ref or a
  #     remote-tracking ref for it) is skipped: `--is-ancestor X X` is
  #     always true, so comparing a branch against itself reports "merged"
  #     for work that has not landed. That fires on a repo with no
  #     `origin/main` when the branch under test is the one checked out with
  #     an upstream of its own — the `@{upstream}` fallback then resolves to
  #     the branch itself and drives a live spec to Merged.
  local base_ref='' base_sha='' remote_head='' upstream_ref=''
  remote_head=$("$git_bin" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || printf '')
  upstream_ref=$("$git_bin" rev-parse --symbolic-full-name --verify --quiet '@{upstream}' 2>/dev/null || printf '')
  for candidate in 'refs/remotes/origin/main' \
                   'refs/remotes/origin/master' \
                   "$remote_head" \
                   "$upstream_ref"; do
    [[ -n "$candidate" ]] || continue
    # `[^/]+` keeps the skip to a remote-tracking ref FOR this branch —
    # a bare `*` would also swallow e.g. refs/remotes/origin/release/<branch>.
    # The quoted "$branch" is matched literally, not as a regex.
    if [[ "$candidate" == "refs/heads/$branch" ]] \
      || [[ "$candidate" =~ ^refs/remotes/[^/]+/"$branch"$ ]]; then
      continue
    fi
    base_sha=$("$git_bin" rev-parse --verify --quiet "${candidate}^{commit}" 2>/dev/null || printf '')
    if [[ -n "$base_sha" ]]; then
      base_ref="$candidate"
      break
    fi
  done

  if [[ -z "$base_ref" ]]; then
    # No usable base ref — caller should treat this as "indeterminate"
    # and surface a warning rather than aborting.
    return 0
  fi

  # (c) A branch whose tip is IDENTICAL to the trunk tip is indeterminate.
  #     That is how a brand-new spec — branch cut from the trunk, spec.md
  #     written but not yet committed, no PR — landed in Linear as Merged on
  #     its very first push (#90): parser::lifecycle_phase short-circuits a
  #     `merged` hint straight past the artifact ladder to the terminal
  #     state.
  #
  #     Read the limits of this guard honestly:
  #
  #     * It is NOT free. A branch merged by FAST-FORWARD leaves the trunk
  #       tip identical to the branch tip, so it is the same graph as a
  #       never-started branch and now reads indeterminate where it used to
  #       read `merged`. That trades a false positive (unstarted work driven
  #       terminal) for a false negative (landed work left to the artifact
  #       ladder, i.e. #72's direction) — the safer side, but a real loss.
  #     * It is NOT complete. A branch cut from a STALE local trunk has no
  #       commits of its own yet its tip differs from the trunk tip, so it
  #       still reports `merged` — the full #90 symptom, reachable after any
  #       `fetch` without `pull`. Merge-by-squash and merge-by-rebase are the
  #       mirror gap: the branch tip never enters the trunk's history, so
  #       they read `open`.
  #
  #     Reachability alone cannot close either gap: "never started" and
  #     "merged" are genuinely the same shape in the commit graph. Doing it
  #     properly needs a signal from outside the graph (does this branch's
  #     history carry a commit for `specs/NNN-*`?), which this primitive
  #     cannot see — it is handed a branch name and nothing else. Tracked on
  #     #90 rather than guessed at here.
  if [[ "$branch_sha" == "$base_sha" ]]; then
    return 0
  fi

  # (d) `git merge-base --is-ancestor A B` returns 0 iff A is reachable
  #     from B. We report "merged" when the branch tip is reachable from the
  #     trunk tip and the two differ — see (c) for what that does and does
  #     not establish.
  if "$git_bin" merge-base --is-ancestor "$branch_sha" "$base_sha" >/dev/null 2>&1; then
    printf 'merged\n'
  else
    printf 'open\n'
  fi
}

# ---------------------------------------------------------------------------
# git_helpers::last_touched <path>
#
# Echoes the modification time of <path> in ISO 8601 (UTC, second
# precision: YYYY-MM-DDTHH:MM:SSZ). Used by the spec Issue's memory
# block (FR-004) so operators can see "when did this spec last change
# on disk" without leaving Linear.
#
# Cross-platform: GNU coreutils `stat` and BSD `stat` (macOS) use
# incompatible flag sets. We try the GNU form first (`stat -c %Y`) and
# fall back to the BSD form (`stat -f %m`). Both emit the mtime as a
# Unix epoch integer, which we then format via `date -u`. macOS `date`
# uses `-r <epoch>` to interpret the integer; GNU `date` uses
# `-d @<epoch>`. We try both.
#
# Empty stdout means we couldn't read the file — caller should treat it
# as "unknown" rather than aborting.
# ---------------------------------------------------------------------------
git_helpers::last_touched() {
  local target="${1:-}"
  if [[ -z "$target" || ! -e "$target" ]]; then
    return 0
  fi

  local epoch=''
  if epoch=$(stat -c %Y "$target" 2>/dev/null); then
    : # GNU stat succeeded
  elif epoch=$(stat -f %m "$target" 2>/dev/null); then
    : # BSD stat succeeded
  else
    return 0
  fi

  if [[ -z "$epoch" || ! "$epoch" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  local formatted=''
  if formatted=$(date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null); then
    printf '%s\n' "$formatted"
  elif formatted=$(date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null); then
    printf '%s\n' "$formatted"
  fi
}

# ---------------------------------------------------------------------------
# git_helpers::iso_to_epoch <iso-8601>          (spec 003 — recency-comparison §2)
#
# Converts a strict ISO-8601 timestamp (e.g. the `%cI` committer date
# `2026-05-20T14:02:11+00:00`, or a `Z`-suffixed UTC form) to a Unix epoch
# integer on stdout. Mirrors the dual GNU/BSD `date` pattern that
# git_helpers::last_touched already relies on, but in the parse direction:
#
#   * GNU coreutils: `date -d "<iso>" +%s` accepts ISO-8601 directly.
#   * BSD/macOS:     `date -j -f "<fmt>" "<iso>" +%s` needs an explicit
#                    input format. ISO-8601 admits two zone spellings —
#                    a literal `Z` and a numeric `±HH:MM` offset — so we try
#                    both BSD format strings. macOS `date` rejects the colon
#                    in `%z`, so we normalise `+00:00` → `+0000` first.
#
# Empty stdout (exit 0) means the string could not be parsed — the caller
# treats recency as `unavailable` and falls back to phase-ordering alone
# (recency-comparison §2: "do not fabricate a comparison"). MUST NOT use
# mtime; this is a pure string→epoch transform with no filesystem access.
# ---------------------------------------------------------------------------
git_helpers::iso_to_epoch() {
  local iso="${1:-}"
  if [[ -z "$iso" ]]; then
    return 0
  fi

  local epoch=''
  # GNU first: a single permissive parser handles every ISO-8601 spelling.
  if epoch=$(date -d "$iso" +%s 2>/dev/null) && [[ -n "$epoch" ]]; then
    printf '%s\n' "$epoch"
    return 0
  fi

  # BSD/macOS fallback. macOS `strptime` cannot read the colon in a numeric
  # zone offset, so collapse `+00:00` → `+0000` before handing it over.
  local normalised="${iso/Z/+0000}"
  # Strip the colon from a trailing ±HH:MM offset only (last 6 chars shape).
  if [[ "$normalised" =~ ^(.*T[0-9:]+)([+-][0-9]{2}):([0-9]{2})$ ]]; then
    normalised="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
  fi
  if epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$normalised" +%s 2>/dev/null) \
      && [[ -n "$epoch" ]]; then
    printf '%s\n' "$epoch"
    return 0
  fi
  # Last resort: a zone-less ISO form (no offset at all).
  if epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${iso%Z}" +%s 2>/dev/null) \
      && [[ -n "$epoch" ]]; then
    printf '%s\n' "$epoch"
    return 0
  fi
  # Unparseable — recency unavailable.
  return 0
}

# ---------------------------------------------------------------------------
# git_helpers::spec_dir_last_commit <spec_dir>   (spec 003 — recency-comparison §1)
#
# Echoes the ISO-8601 committer date (`%cI`, e.g.
# `2026-05-20T14:02:11+00:00`) of the most recent commit that TOUCHED
# <spec_dir>, or the empty string when no commit in this worktree's history
# touches the directory (Edge Case 1 → recency signal `unavailable`).
#
# This is the recency comparator's disk key (FR-053). It MUST use the git
# committer date — NEVER `stat`/mtime — because the committer date is
# clone/checkout-stable and reflects when the change landed in THIS
# worktree's history. The mtime-based git_helpers::last_touched (above) is
# RETAINED only for the FR-004 memory-block human display and MUST NOT be
# used as the recency comparator.
#
# Runs `git -C <worktree-or-cwd>` implicitly via the captured git binary so
# the lookup works from any worktree; the pathspec `-- <spec_dir>` restricts
# the log to commits affecting the spec directory.
# ---------------------------------------------------------------------------
git_helpers::spec_dir_last_commit() {
  local spec_dir="${1:-}"
  if [[ -z "$spec_dir" ]]; then
    return 0
  fi

  local git_bin="${_GIT_HELPERS_GIT_BIN:-git}"
  local iso=''
  # `git log -1 --format=%cI -- <dir>` echoes a single ISO-8601 line, or
  # nothing (exit 0) when no commit touches the pathspec. The `|| true`
  # guards against a non-zero exit on a brand-new repo with no commits.
  iso=$("$git_bin" log -1 --format=%cI -- "$spec_dir" 2>/dev/null || true)
  if [[ -n "$iso" ]]; then
    printf '%s\n' "$iso"
  fi
}

# ---------------------------------------------------------------------------
# git_helpers::worktrees_touching_spec <feature_number>
#                                          (spec 003 — recency-comparison §4)
#
# Emits one line per worktree whose checkout contains a `specs/<NNN>-*/`
# directory, in the form:
#
#     <commit_epoch>\t<worktree_path>\t<branch>
#
# where <commit_epoch> is the Unix-epoch conversion of that worktree's
# spec-dir last-commit ISO date (§1), <worktree_path> is the absolute
# worktree root, and <branch> is the checked-out branch (empty for detached
# HEAD). Worktrees that do NOT contain the spec dir are omitted entirely.
#
# Ranking contract (FR-058 / FR-059): the canonical worktree is the line
# with the MAXIMUM commit_epoch — the most recent spec-dir commit, NEVER the
# branch name or filesystem mtime. Ties (identical epochs) resolve to the
# invoking worktree as canonical; both tied worktrees still appear in the
# emitted touching set. This function only enumerates + ranks; the caller
# (reconcile::compute_drift / the WARNING emitter) selects the max.
#
# A worktree whose spec-dir commit is unavailable (dir present but no commit
# touches it — uncommitted spec) is emitted with a `0` epoch so it sorts
# below any real commit but still appears in the touching set.
# ---------------------------------------------------------------------------
git_helpers::worktrees_touching_spec() {
  local feature_number="${1:-}"
  if [[ -z "$feature_number" || ! "$feature_number" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  local git_bin="${_GIT_HELPERS_GIT_BIN:-git}"
  local invoking_root=''
  invoking_root=$("$git_bin" rev-parse --show-toplevel 2>/dev/null || printf '')

  # Tie-break ordering (FR-058 / FR-059): the caller ranks the emitted rows
  # with a STABLE descending sort by epoch and takes the first row, so on an
  # equal-epoch tie whichever row appears FIRST in this stream wins. The
  # documented contract is that the invoking worktree wins such ties, but
  # git_helpers::list_worktrees emits in `git worktree list` (porcelain)
  # order — the MAIN worktree first, not necessarily the invoking one. We
  # therefore buffer the invoking worktree's row and the rest separately,
  # then print the invoking row AHEAD of the others. A strictly-greater
  # epoch elsewhere still sorts above the invoking row in the caller's
  # descending sort, so the non-tie path is unchanged; only exact ties are
  # affected, and they now resolve to the invoking worktree as documented.
  # When invoking_root is empty (rev-parse failed) nothing is held back and
  # ordering falls through to porcelain order unchanged.
  local invoking_line='' other_lines=''

  local path branch
  while IFS=$'\t' read -r path branch; do
    [[ -n "$path" ]] || continue

    # Find a specs/<NNN>-*/ dir inside this worktree. `compgen -G` globs
    # without nullglob side effects; the first match is sufficient because a
    # well-formed repo carries exactly one spec dir per feature number.
    local matches match spec_dir=''
    matches=$(compgen -G "${path%/}/specs/${feature_number}-*" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
      while IFS= read -r match; do
        if [[ -d "$match" ]]; then
          spec_dir="$match"
          break
        fi
      done <<< "$matches"
    fi
    [[ -n "$spec_dir" ]] || continue

    # The spec-dir last commit must be read from THIS worktree's history.
    # `git -C <path> log` scopes the query to the worktree's own refs.
    local iso epoch
    iso=$("$git_bin" -C "$path" log -1 --format=%cI -- "$spec_dir" 2>/dev/null || true)
    if [[ -n "$iso" ]]; then
      epoch=$(git_helpers::iso_to_epoch "$iso")
    fi
    [[ -n "${epoch:-}" ]] || epoch=0

    local row
    row="$(printf '%s\t%s\t%s' "$epoch" "$path" "$branch")"

    # Hold the invoking worktree's row back so it can be emitted FIRST (the
    # equal-epoch tie-break, below); every other row keeps its porcelain
    # order.
    if [[ -n "$invoking_root" && "$path" == "$invoking_root" ]]; then
      invoking_line="$row"
    else
      other_lines+="${row}"$'\n'
    fi
  done < <(git_helpers::list_worktrees)

  # Invoking worktree first (tie-break winner), then the rest in porcelain
  # order. printf '%s' on the (newline-terminated) accumulator avoids adding
  # a spurious trailing blank line.
  if [[ -n "$invoking_line" ]]; then
    printf '%s\n' "$invoking_line"
  fi
  if [[ -n "$other_lines" ]]; then
    printf '%s' "$other_lines"
  fi
}
