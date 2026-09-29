---
name: ralph-review
description: Compatibility entry point for an explicitly requested /ralph-review; delegates to the installed official revmux skill rather than running a second autonomous review pipeline. Not an implementation trigger.
argument-hint: "[base-branch]"
---

# Review via revmux

The former multi-stage custom review/fix loop is retired. This entry point retains the familiar command, not a second implementation of the review engine.

1. Read the host's current review, approval, model and resource policy.
2. Activate the installed official `revmux` skill and its matching CLI documentation. If absent, report that prerequisite; do not silently fall back to the retired loop or install without the host's authorization.
3. Resolve the requested scope and PR target (normally main). Review the whole task diff on repeated rounds, excluding unrelated changes; justify another base.
4. Use the host-approved profile. Preserve required independent model coverage and explicit model choices; do not silently substitute after a provider/quota error. Keep read-only review separate from implementation and tests.
5. The parent adjudicates findings by agreed functionality, likely consequence and proportionate cost. Fixes require implementation authorization; already authorized in-scope fixes need no new approval per finding. Automatically choose the recommended next fix/re-review action within that authorization; retain the explicitly selected profile/models rather than silently choosing cheaper coverage. Hypothetical corner cases and severity labels are not automatic scope expansion.
6. For an authorized review/fix cycle, use at most five total rounds, initial included, across continuations; stop earlier when sufficient. The cap ends review, not the task. Do not restart counters, stack another legacy review loop, require a clean report, or escalate residual nits automatically.
7. Preserve concrete secret, destructive-action, access and external-publication boundaries. Run sufficient functional checks in the implementation/parent context, not in the read-only reviewers.
8. Follow the host's supervision and terminal-delivery contract. Report degraded coverage truthfully and retain the review archive for recovery.

Use the official skill for CLI syntax, task-round preparation and output parsing; do not duplicate its recipe here. This command does not merge, publish, or change model/runtime configuration.
