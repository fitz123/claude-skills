---
name: dual-review
description: Legacy alias — dual-review was renamed to multi-review with Gemini added as a third reviewer. Triggers preserved for muscle memory: dual review, /dual-review, co-review, cross-review, opus+codex review. Will be removed in v3.0.0.
---

# Dual Review (legacy alias)

This skill has been renamed to `multi-review` and now runs three reviewers (Codex + Opus + Gemini) instead of two. Invoke `/multi-review` (or `claude-skills:multi-review` via the Skill tool) to use the new flow.

## What to do when this skill is triggered

Do not run a review from this file. Instead, invoke the `multi-review` skill directly — either via the slash command `/multi-review` or by calling the `Skill` tool with the `multi-review` name. Pass through any arguments (`<base-branch>`) the user supplied with `/dual-review`.

## Deprecation

Scheduled for removal in `claude-skills` v3.0.0. Update any aliases, docs, or CLAUDE.md files that reference `/dual-review` to use `/multi-review` directly.
