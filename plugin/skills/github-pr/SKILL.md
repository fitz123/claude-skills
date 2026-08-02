---
name: github-pr
description: "Workflow + scripts for a CI-first iterative GitHub PR review cycle: wait for green current-head CI, request Copilot, address findings, and repeat without reviewing known-bad heads. Use when iterating on a PR with the Copilot Code Review bot. Triggered by 'github pr', 'watch pr', 're-request copilot', 'resolve pr threads', or any PR-cycle handoff."
argument-hint: "[pr-number]"
allowed-tools:
  - Bash(gh:*)
  - Bash(bash:*)
  - Bash(sleep:*)
  - Read
---

# github-pr — Copilot-aware PR review loop

This skill exists because the Copilot review cycle has six non-obvious gotchas
that silently waste review runs or polling time if you miss them:

1. **CI must be green before requesting Copilot.** Reviewing a head while CI is
   pending can waste a review when tests then force another push. The poller
   defers its request until all current-head checks succeed; failed CI exits
   non-zero without spending a request.
2. **Version-release PRs skip Copilot.** Mechanical release branches/titles
   matching the documented version convention still wait for current-head CI,
   then finish without requesting or waiting for Copilot.
3. **Copilot does NOT auto-re-review on every push.** The first review may be
   triggered by PR creation; subsequent pushes require an explicit re-request
   or Copilot stays silent forever.
4. **The REST `requested_reviewers=Copilot` endpoint silently dedupes after
   ~4 rapid re-requests on the same PR.** It returns HTTP 201 with empty
   `requested_reviewers`, no `review_requested` event fires, no review is
   queued. The `request-copilot-rereview.sh` script checks the timeline event
   count and falls back to `@copilot please re-review` when REST silently
   no-ops. The fallback is idempotent per PR head for a short cooldown.
5. **Copilot replies to `@copilot` comments as a COMMENT (`copilot-swe-agent`),
   not as a formal Review.** A watcher that only polls `reviews[]` waits
   forever. The poller watches BOTH `reviews[]` and Copilot comments.
6. **A fallback request can terminate without review activity.** GitHub records
   `copilot_work_finished_failure` in the PR timeline. The poller accepts this
   only after the marked current-head request and only when no newer Copilot
   trigger supersedes it; green CI remains mandatory.

Plus: background polling loops that only emit output at the end are
indistinguishable from hung processes when an upstream agent is watching.
This skill's poller emits a heartbeat line every cycle so liveness is visible.

## The cycle (per round of fixes)

1. **Push fixes** addressing the prior Copilot review.
2. **Resolve any threads** your push addresses:
   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/github-pr/scripts/resolve-all-threads.sh <pr-number>
   ```
3. **Start the CI-gated poller** in background. It waits while current-head CI
   is pending, exits non-zero without requesting Copilot if CI fails, and only
   requests Copilot after CI succeeds. It then waits for current-head Copilot
   activity or a correlated terminal no-review outcome:
   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/github-pr/scripts/poll-pr-review.sh <pr-number>
   ```
   The timeout covers the poll cycle. Exit codes are `0` for a completed green-CI
   review phase, `2` for failed CI, `3` for a head change, `4` for a query error,
   and `124` for timeout.

   Do **not** call `request-copilot-rereview.sh` while CI is pending. Direct use
   is only appropriate after independently proving current-head CI is green;
   the poller normally handles the request and its dedupe fallback.

   A PR is treated as a version release only when both branch and title match:
   `release-X.Y.Z` or `release/vX.Y.Z`, with `chore: release X.Y.Z`,
   `Release X.Y.Z`, or `Release vX.Y.Z`. Such PRs wait only for CI.

   When launched from Telegram, export `GH_PR_NOTIFY_TARGET=<chat_id>` and,
   for a forum topic, `GH_PR_NOTIFY_THREAD=<topic_id>`. Completion delivery is
   absent-safe and does not replace the parent task's terminal report.
4. **Triage** findings (severity + verify against code), push fixes, and repeat
   from step 1 so every re-review is gated by green current-head CI.

### First PR-open invocation

For the first poll after `gh pr create`, repository-level settings may already
have auto-requested Copilot. The poller never adds another request while CI is
pending. Once CI is green, it accepts existing current-head Copilot activity or
an existing pending reviewer; otherwise it requests Copilot exactly once.
Repository-level automatic first-review settings are outside this skill.

## Useful one-liners (no scripts needed)

```bash
# List unresolved threads with file:line + body preview
gh api graphql -f query='{repository(owner:"OWNER",name:"REPO"){pullRequest(number:NN){reviewThreads(first:50){nodes{id isResolved comments(last:1){nodes{path line author{login} body}}}}}}}' \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | {path: .comments.nodes[0].path, line: .comments.nodes[0].line, body_head: (.comments.nodes[0].body[0:300])}]'

# All inline review comments since a timestamp
gh api repos/OWNER/REPO/pulls/NN/comments \
  --jq '[.[] | select(.created_at > "ISO-TIMESTAMP") | {author: .user.login, path, line, body}]'

# Check overall PR state
gh pr view NN --json reviewDecision,reviews,statusCheckRollup
```

## Gotchas to remember

- **Two Copilot login forms** depending on event type:
  - Formal reviews: `copilot-pull-request-reviewer` (Bot type)
  - Comment replies to `@copilot`: `copilot-swe-agent` (User type)
  - Re-request via REST API: literal token `Copilot` (capitalized). The actual
    bot login is rejected as "not a collaborator". HTTP 201 doesn't guarantee a
    review will fire — see "silently dedupes" gotcha above.
- **CI state field**: `gh pr checks --json state` returns `SUCCESS`/`FAILURE`/
  `IN_PROGRESS`/`PENDING`/`QUEUED`/`SKIPPED`/`NEUTRAL`/`CANCELLED`/`TIMED_OUT`/
  `ACTION_REQUIRED`, not `COMPLETED`. The poller combines structured `state`
  and `completedAt`, including Go's zero time, and requires every check to be
  `SUCCESS`, `SKIPPED`, or `NEUTRAL`. Zero checks keep the poller's existing
  eligible behavior and are reported explicitly rather than silently inferred.
- **`gh pr checks --json status` doesn't work** — the field is `state`, not
  `status`. Same for the items inside the array.
- **`(eval):1: == not found` errors** from background-launched polling loops
  usually mean a jq filter with `==` got reparsed by the harness when passed as
  a one-liner string. Write the loop to a file and execute the file instead;
  that's why the scripts in this skill exist as files.
- **Heartbeat the poller.** A poll loop that emits only at completion is
  indistinguishable from a hung shell when a watching agent (or human) checks
  `wc -c` on the output. The script in this skill prints per-iteration lines.
- **A terminal Copilot failure is not CI success.** The poller stops expecting
  a review only when `copilot_work_finished_failure` occurs after the fallback
  marker for the current PR head and no newer Copilot request or `@copilot`
  trigger supersedes that fallback in timeline order. It re-evaluates that
  ordering only from complete timeline snapshots, preserves the last known
  state for diagnostics across transient lookup failures, requires a fresh
  complete snapshot before exiting on terminal evidence, still requires green
  CI, and callers should treat the explicit terminal-failure line as a
  no-review outcome rather than review approval.
- **Empty `start_*` vs typo guard.** If `gh pr view` errors transiently,
  capture in the loop body might come back empty. The poller falls back to the
  baseline value to avoid bash's `[ "" -gt 0 ]` error.
- **PR ready ≠ merged.** Confirm via `gh pr view NN --json state,mergedAt` —
  don't trust a stale view from before the operator merged.

## When to NOT use this skill

- Single-shot review fetch ("what did Copilot say?"): a direct
  `gh api .../pulls/NN/comments` is faster than spinning up a poller.
- Repos where Copilot Code Review isn't enabled. The re-request will succeed
  but no review will arrive — the poller will just hit its timeout.
- Non-GitHub PR systems (e.g. Gitea, GitLab) — this skill is GitHub-specific.
