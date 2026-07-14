# Stop GitHub PR polling after Copilot terminal failure

## Overview

The `github-pr` poller currently waits its full 600-second budget when the `@copilot please re-review` fallback starts Copilot Agent but GitHub immediately records `copilot_work_finished_failure`. Treat that timeline event as a terminal no-review outcome for the current fallback request, stop waiting for Copilot, and continue waiting only for mandatory CI completion.

## Context

- Affected script: `plugin/skills/github-pr/scripts/poll-pr-review.sh`
- Workflow documentation: `plugin/skills/github-pr/SKILL.md`
- Real evidence: public PRs recorded `copilot_work_finished_failure` about five seconds after the fallback comment, while the poller continued to 604 seconds.
- The timeline API exposes the generic terminal event but not the UI's detailed reason, so detection must not depend on credit-specific text.
- Existing review/comment success detection, final-state output, CI gating, timeout behavior, and request idempotency must remain intact.

## Development Approach

- Keep the change minimal and shell-only; add no dependency or generalized state machine.
- Correlate a failure to the current PR head's marked fallback request so old or unrelated timeline failures cannot satisfy the condition.
- A terminal Copilot failure is a review-service no-op, not CI success: the poller may stop waiting for Copilot but exits only after CI is complete.

## Testing Strategy

Add a self-contained shell regression test with a fake `gh` executable. Cover terminal-failure early continuation, stale/unrelated failure rejection, and preserved successful review/comment behavior without calling GitHub.

## Implementation Steps

### Task 1: Detect current-request Copilot terminal failure
- [ ] Update `poll-pr-review.sh` to locate the current-head fallback request marker and detect a later `copilot_work_finished_failure` timeline event.
- [ ] Treat a correlated terminal failure as a Copilot no-op, emit an explicit outcome line, and continue waiting only until CI completes instead of exhausting the Copilot timeout.
- [ ] Preserve existing current-head review/comment detection, pre-flight request behavior, CI requirement, timeout semantics, and final-state diagnostics.
- [ ] Add focused shell regression tests for a correlated failure, an old/unrelated failure, and normal Copilot activity.
- [ ] Update `plugin/skills/github-pr/SKILL.md` to document the terminal-failure behavior and caller expectations.
- [ ] Run the focused tests and shell syntax checks; all must pass.

## Validation Commands

```bash
bash plugin/skills/github-pr/tests/poll-pr-review-test.sh
bash -n plugin/skills/github-pr/scripts/poll-pr-review.sh
bash -n plugin/skills/github-pr/scripts/request-copilot-rereview.sh
```

## Post-Completion

Open a PR in `fitz123/claude-skills`; do not merge without explicit authorization.
