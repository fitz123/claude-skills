---
name: multi-review
description: Run three independent reviewers (Codex via thinking-tools:ask-codex + a fresh Opus subagent via Task + Gemini via claude-skills:ask-gemini) in parallel against the current branch, merge findings, then write all questions to a markdown file for single-pass plannotator review before applying anything. Use when user says "multi review", "/multi-review", "triple review", "dual review" (legacy), "co-review", "cross-review", "opus+codex+gemini review", or asks for a multi-reviewer code review.
argument-hint: "[base-branch]"
allowed-tools:
  - Bash(cargo:*)
  - Bash(git:*)
  - Bash(go:*)
  - Bash(make:*)
  - Bash(npm:*)
  - Bash(plannotator:*)
  - Bash(pnpm:*)
  - Bash(pytest:*)
  - Bash(python:*)
  - Bash(python3:*)
  - Bash(ruff:*)
  - Bash(yarn:*)
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - Task
  - Skill
  - AskUserQuestion
---

# Multi Review

Codex (via `thinking-tools:ask-codex`), a fresh Opus subagent (via the `Task` tool with `subagent_type: "general-purpose"`), and Gemini (via `claude-skills:ask-gemini`) review the branch in parallel. Findings merged, written to one markdown file, opened with `plannotator annotate` for single-pass review, applied in one commit. Save pre-review HEAD as the rollback SHA.

## Prerequisites

This skill depends on two other marketplace plugins:
- **`thinking-tools`** (provides the model-invocable `ask-codex` Skill — `/plugin install thinking-tools@<source>`).
- **`plannotator`** (provides the `plannotator` CLI on `PATH`; the skill shells out to `plannotator annotate <findings-file>` via Bash. Note: the bundled `/plannotator-annotate` slash command has `disable-model-invocation: true` and is user-only by design; the model must invoke the bare CLI, not the slash command. `/plugin install plannotator@plannotator`.)
- **`gemini` CLI on `PATH`** (typically `/opt/homebrew/bin/gemini` on macOS via `brew install gemini-cli` or similar). Auth via `GEMINI_API_KEY` env or `gcloud auth application-default login`. The skill invokes Gemini through the sibling `claude-skills:ask-gemini` Skill, which wraps `gemini -p "<prompt>" --approval-mode plan` for read-only review mode.

## Refuse if unsafe

Dirty tree; in-progress git op; detached HEAD; branch is `main`/`master`/`develop`/`trunk`; no commits ahead of base. Flag any submodule pointer changes — they're not reviewed inline.

## Launch reviewers in parallel

Before sending the prompt, run `git diff {base}...HEAD` in the orchestrator and inline its output inside the `<diff>...</diff>` block of the prompt template below. **Don't rely on each reviewer running `git diff` themselves** — Gemini in `--approval-mode plan` cannot execute shell commands, so a shell-reference-only prompt fails for Gemini even though Codex/Opus would handle it.

Single message:
1. Codex — invoke `thinking-tools:ask-codex` via the `Skill` tool with the prompt below; capture findings as data.
2. Opus — `Task` tool with `subagent_type: "general-purpose"` using the same prompt.
3. Gemini — invoke `claude-skills:ask-gemini` via the `Skill` tool with the same prompt.

Retry once on non-JSON. If a reviewer dies twice, proceed with the survivors and note the gap.

### Adversarial review prompt

```
<role>You are performing an adversarial code review. Break confidence in the change, do not validate it.</role>
<task>Review the diff provided below. For additional context-gathering, use ONLY the `codebase_investigator` subagent (Gemini's plan-mode default allowlist) or direct read tools (`read_file`, `glob`, `grep_search`). Do NOT invoke other subagents. Do not edit/write/commit.</task>
<operating_stance>Default to skepticism. Happy-path-only is a real weakness.</operating_stance>
<attack_surfaces>
auth, tenant isolation, trust boundaries; data loss / corruption / irreversible state; rollback safety, retries, idempotency; races, ordering, re-entrancy; empty/nil/timeout/degraded-dependency; schema drift, migration hazards; observability gaps.
</attack_surfaces>
<finding_bar>Material findings only. Each must answer: what goes wrong, why this path is vulnerable, impact, concrete fix. One strong finding > several weak ones.</finding_bar>
<grounding>Defensible from actual code. Don't invent. Honest confidence scores.</grounding>
<diff>
{inline the full output of `git diff {base}...HEAD` here — the orchestrator resolves this before sending the prompt}
</diff>
<output>
Return JSON only, no fence:
{ "verdict": "approve"|"needs-attention", "summary": "...",
  "findings": [{ "severity": "critical|high|medium|low", "title": "...", "body": "...",
    "file": "...", "line_start": N, "line_end": N, "confidence": 0.0-1.0, "recommendation": "..." }],
  "next_steps": ["..."] }
</output>
```

## Merge and triage

For each finding: verify against actual code at `file:line_start..line_end` (discard on drift). Match across reviewers by file + overlapping lines + same root cause; min confidence wins. Drop `min_confidence < 0.4`.

```
to ask:    N
discarded: K (low-signal + false positives)
gap:       none | Codex | Opus | Gemini | <multiple, comma-separated>
```

`to ask == 0` → report clean, stop.

## Write findings + plannotator review

`/tmp/multi-review-questions-$RANDOM.md`, severity desc:

```markdown
# multi-review findings — <branch> vs <base>

## 1. <title>

- severity: high
- reviewers: Codex+Opus+Gemini
- file: `path:line-line`
- finding: <2-4 sentences>
- recommendation: <combined, or per-reviewer if divergent>

decision:
- [ ] apply
- [ ] skip
- [ ] other: <comment>

---
```

Invoke `plannotator annotate <findings-file>` via Bash (the CLI lives at `~/.local/bin/plannotator` and is what the slash command runs internally). Fallback if unavailable: per-finding `AskUserQuestion` in severity order.

## Confirm

Print a one-line-per-finding table. Ask: `Apply all` / `Cancel`.

## Apply + commit

Apply each `apply`'d fix. Stage modified files by name. Run discovered tests/lint once; on failure, fix and rerun until pass. Commit `fix: address multi-review findings`. Hook failure → stop, surface output, give rollback SHA. Never `--no-verify`, never amend.

## Final report

```
✓ applied: N
✗ skipped: K
⚠ unresolvable: U

reviewers:        Codex+Opus+Gemini | Codex+Opus | Codex+Gemini | Opus+Gemini | Codex only | Opus only | Gemini only | none
discarded:        count (low-signal + FPs)
submodule notes:  pointer changes flagged in Step 0 (not reviewed inline)
pre-review HEAD:  <sha>
```

Any `⚠` → don't say "ready".
