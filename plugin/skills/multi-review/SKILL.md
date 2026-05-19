---
name: multi-review
description: Run three independent reviewers (Codex via direct `codex exec`, a fresh Opus subagent via `Task`, and Gemini via the `gemini` CLI) in parallel against the current branch, merge findings, then write all questions to a markdown file for single-pass plannotator review before applying anything. Use when user says "multi review", "/multi-review", "triple review", "dual review" (legacy), "co-review", "cross-review", "opus+codex+gemini review", or asks for a multi-reviewer code review.
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

Codex (via direct `codex exec`), a fresh Opus subagent (via the `Task` tool with `subagent_type: "general-purpose"`), and Gemini (via the `gemini` CLI) review the branch in parallel. Findings merged, written to one markdown file, opened with `plannotator annotate` for single-pass review, applied in one commit. Save pre-review HEAD as the rollback SHA.

## Prerequisites

This skill depends on two other marketplace plugins:
- **`thinking-tools`** (provides the model-invocable `ask-codex` Skill — `/plugin install thinking-tools@<source>`).
- **`plannotator`** (provides the `plannotator` CLI on `PATH`; the skill shells out to `plannotator annotate <findings-file>` via Bash. Note: the bundled `/plannotator-annotate` slash command has `disable-model-invocation: true` and is user-only by design; the model must invoke the bare CLI, not the slash command. `/plugin install plannotator@plannotator`.)
- **`gemini` CLI on `PATH`** (typically `/opt/homebrew/bin/gemini` on macOS via `brew install gemini-cli` or similar). Auth via `GEMINI_API_KEY` env or `gcloud auth application-default login`. `multi-review` invokes the CLI directly via `Bash` (see Launch step below) — Gemini's default model is used (no `-m` pin) so the skill picks up CLI default-model upgrades automatically. The sibling `claude-skills:ask-gemini` Skill is for standalone interactive use; `multi-review` does NOT route through it (would serialize wall-clock work — see Parallelism contract below).

## Refuse if unsafe

Dirty tree; in-progress git op; detached HEAD; branch is `main`/`master`/`develop`/`trunk`; no commits ahead of base. Flag any submodule pointer changes — they're not reviewed inline.

## Launch reviewers in parallel

Before launching, run `git diff {base}...HEAD` in the orchestrator and inline its output inside the `<diff>...</diff>` block of the prompt template below. **Don't rely on each reviewer running `git diff` themselves** — Gemini in `--approval-mode plan` cannot execute shell commands, so a shell-reference-only prompt fails for Gemini even though Codex/Opus would handle it.

### Parallelism contract (load-bearing — read this)

All three reviewer invocations **MUST** be dispatched as three tool calls in a **single assistant message**, with **all three set to run in the background**. Empirically verified (Opus+Gemini+Codex against a small diff): with this pattern, wall-clock ≈ max(reviewers) ≈ 54s; without `run_in_background`, the UI serializes foreground tool calls and wall-clock ≈ sum(reviewers) ≈ 112s. Same-message foreground tool calls render and complete in dispatch order — that is sequential in practice. Background mode is the only reliable way to get genuine parallelism in this harness.

**Do NOT route through the `Skill` tool for `thinking-tools:ask-codex` or `claude-skills:ask-gemini` here.** The `Skill` tool *loads* the underlying skill's instructions into the conversation; it does NOT execute the CLI. Following those instructions requires an additional message per reviewer, which adds a serializing round-trip. The `Skill` tool is the right path for standalone interactive use (e.g. someone asking "ask codex about X"); inside `multi-review` we inline the CLI invocations directly with `run_in_background: true` to preserve concurrency.

### The three tool calls (one assistant message, all backgrounded)

1. **Codex — `Bash` tool with `run_in_background: true`** (not `Skill`):

   ```bash
   codex exec \
     --sandbox read-only \
     -c model_reasoning_effort="high" \
     -c stream_idle_timeout_ms=600000 \
     -c project_doc="$HOME/.claude/CLAUDE.md" \
     -c project_doc="./CLAUDE.md" \
     "<the adversarial review prompt below, with the diff already inlined>"
   ```

   **Don't pin `-m <model>`** — let codex use its default. As the CLI's default model updates, the skill benefits automatically. (`model_reasoning_effort="high"` is a behavior setting, not a model pin; keep it for review depth.)

   Returns a background task ID immediately. The CLI runs in the background until codex finishes (2–5 min typical).

2. **Opus — `Task` tool with `run_in_background: true`**, `subagent_type: "general-purpose"`, with the entire adversarial review prompt as the `prompt` argument. Returns an agent ID immediately; the subagent runs concurrently with the two `Bash` reviewers.

3. **Gemini — `Bash` tool with `run_in_background: true`** (not `Skill`):

   ```bash
   gemini --approval-mode plan < /tmp/multi-review-prompt-<random>.txt
   ```

   Write the prompt to a temp file first (`Write` tool to `/tmp/multi-review-prompt-$RANDOM.txt`), then redirect stdin. Don't use `gemini -p "<prompt>"` because inlined diffs blow past shell ARG_MAX (~256KB on macOS) on real PRs. Avoid `cat <prompt-file> | gemini` — pipes-in-bash-tool can trip command-classification heuristics in the harness; plain stdin redirection (`< file`) is the safest form.

After the message returns, the model receives three task IDs (one per reviewer). Wait for the three `<task-notification>` events to fire. Do NOT poll the output files manually — read each output file ONLY after its completion notification arrives. Once all three notifications land, parse JSON from each output file and proceed to the merge step below.

Retry-once-on-non-JSON: if any reviewer's output isn't parseable JSON, re-issue that one call (alone, also `run_in_background: true`). If it fails twice, proceed with the survivors and note the gap.

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
