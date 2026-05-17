---
name: github-pr
description: "Workflow + scripts for an iterative GitHub PR review cycle: create PR, watch for Copilot + CI, address findings, re-request Copilot (REQUIRED — Copilot does not auto-re-review on each push), resolve threads, repeat until clean. Use when iterating on a PR with the Copilot Code Review bot. Triggered by 'github pr', 'watch pr', 're-request copilot', 'resolve pr threads', or any PR-cycle handoff."
argument-hint: "[pr-number]"
allowed-tools:
  - Bash(gh:*)
  - Bash(bash:*)
  - Bash(sleep:*)
  - Read
---

# github-pr — Copilot-aware PR review loop

This skill exists because the Copilot review cycle has three non-obvious gotchas
that silently waste minutes of polling each round if you miss them:

1. **Copilot does NOT auto-re-review on every push.** The first review is
   triggered by PR creation; subsequent pushes require an explicit re-request
   or Copilot stays silent forever.
2. **The REST `requested_reviewers=Copilot` endpoint silently dedupes after
   ~4 rapid re-requests on the same PR.** It returns HTTP 201 with empty
   `requested_reviewers`, no `review_requested` event fires, no review is
   queued. The `request-copilot-rereview.sh` script in this skill checks the
   timeline event count and falls back to `@copilot please re-review` comment
   when REST silently no-ops.
3. **Copilot replies to `@copilot` comments as a COMMENT (`copilot-swe-agent`),
   not as a formal Review.** A watcher that only polls `reviews[]` waits
   forever. The poller in this skill watches BOTH `reviews[]` and Copilot
   comments since baseline.

Plus: background polling loops that only emit output at the end are
indistinguishable from hung processes when an upstream agent is watching.
This skill's poller emits a heartbeat line every cycle so liveness is visible.

## The cycle (per round of fixes)

1. **Push fixes** addressing the prior Copilot review.
2. **Resolve any threads** your push addresses:
   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/github-pr/scripts/resolve-all-threads.sh <pr-number>
   ```
3. **Re-request Copilot** — REQUIRED, easy to forget:
   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/github-pr/scripts/request-copilot-rereview.sh <pr-number>
   ```
   Skip this and step 4 polls forever.
4. **Poll for the next review + CI**. Run in background (`run_in_background: true`)
   so the agent can do other work; heartbeat lines confirm liveness:
   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/github-pr/scripts/poll-pr-review.sh <pr-number>
   ```
5. **Triage** the new findings (severity + verify-against-code). Repeat from 1.

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
  `ACTION_REQUIRED`. NOT `COMPLETED` (that's from a different API). For
  "all settled" use `--json completedAt` + `all(. != null and . != "")`.
- **`gh pr checks --json status` doesn't work** — the field is `state`, not
  `status`. Same for the items inside the array.
- **`(eval):1: == not found` errors** from background-launched polling loops
  usually mean a jq filter with `==` got reparsed by the harness when passed as
  a one-liner string. Write the loop to a file and execute the file instead;
  that's why the scripts in this skill exist as files.
- **Heartbeat the poller.** A poll loop that emits only at completion is
  indistinguishable from a hung shell when a watching agent (or human) checks
  `wc -c` on the output. The script in this skill prints per-iteration lines.
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
