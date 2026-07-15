---
name: multi-review
description: Run three independent reviewers (Codex via direct `codex exec`, a fresh Fable subagent via `Task`, and Gemini via the Antigravity `agy` CLI) in parallel against the current branch, merge findings, then write all questions to a markdown file for single-pass plannotator review before applying anything. Use when user says "multi review", "/multi-review", "triple review", "dual review" (legacy), "co-review", "cross-review", "fable+codex+gemini review", or asks for a multi-reviewer code review.
argument-hint: "[base-branch]"
allowed-tools:
  - Bash(agy:*)
  - Bash(cargo:*)
  - Bash(codex:*)
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

Codex (via direct `codex exec`), a fresh Fable subagent (via the `Task` tool with `subagent_type: "general-purpose"` and `model: "fable"`), and Gemini (via the Antigravity `agy` CLI) review the branch in parallel. Findings merged, written to one markdown file, opened with `plannotator annotate` for single-pass review, applied in one commit. Save pre-review HEAD as the rollback SHA.

## Prerequisites

This skill depends on two marketplace plugins (`thinking-tools`, `plannotator`) plus the Antigravity `agy` CLI:
- **`thinking-tools`** (provides the model-invocable `ask-codex` Skill — `/plugin install thinking-tools@<source>`).
- **`plannotator`** (provides the `plannotator` CLI on `PATH`; the skill shells out to `plannotator annotate <findings-file>` via Bash. Note: the bundled `/plannotator-annotate` slash command has `disable-model-invocation: true` and is user-only by design; the model must invoke the bare CLI, not the slash command. `/plugin install plannotator@plannotator`.)
- **Antigravity `agy` CLI on `PATH`** (`/opt/homebrew/bin/agy` on macOS via `brew install --cask antigravity-cli`, which links the `antigravity` binary to `agy`). This is the **replacement for the old `gemini` CLI** — Google discontinued the free "Gemini Code Assist for individuals" OAuth tier in `gemini` (it now errors with `IneligibleTierError` / "migrate to the Antigravity suite") and routes individuals to the Antigravity CLI. `agy` runs the same Gemini models. Auth once interactively: run bare `agy` and complete Google Sign-In with your account; the OAuth token is stored in the **macOS Keychain** (not in a file; `~/.gemini/` holds only config, logs, and the installation id). `multi-review` invokes `agy` directly via `Bash` (see Launch step below) — its default model is used (no `--model` pin) so the skill picks up CLI default-model upgrades automatically. The sibling `claude-skills:ask-gemini` Skill is for standalone interactive use; `multi-review` does NOT route through it (would serialize wall-clock work — see Parallelism contract below).
- **`agy` MUST run OUTSIDE Claude Code's Bash sandbox.** Unlike the old `gemini` CLI (token in a plain file `~/.gemini/oauth_creds.json`, readable under the sandbox), `agy` reads its token from the **macOS Keychain**, and the sandbox blocks the `securityd` Mach lookup. A sandboxed `agy` therefore fails with `error getting token source: You are not logged into Antigravity`. Fix: add `"agy:*"` to `sandbox.excludedCommands` in your Claude Code settings (same as the existing `codex:*` entry) so `agy` runs unsandboxed and can reach the Keychain. Without this the Gemini reviewer silently degrades to a `gap`.

## Refuse if unsafe

Dirty tree; in-progress git op; detached HEAD; branch is `main`/`master`/`develop`/`trunk`; no commits ahead of base. Flag any submodule pointer changes — they're not reviewed inline.

## Launch reviewers in parallel

Before launching, run `git diff {base}...HEAD` in the orchestrator and inline its output inside the `<diff>...</diff>` block of the prompt template below. **Don't rely on each reviewer running `git diff` themselves** — for `agy` the full prompt (with the diff already inlined) is written to a temp file that `agy` reads, so it reviews from the inlined diff and never needs to roam the repo or run shell commands. A shell-reference-only prompt would force unnecessary tool use; inlining keeps all three reviewers reviewing identical input.

### Parallelism contract (load-bearing — read this)

All three reviewer invocations **MUST** be dispatched as three tool calls in a **single assistant message**, with **all three set to run in the background**. Empirically verified (Fable+Gemini+Codex against a small diff): with this pattern, wall-clock ≈ max(reviewers) ≈ 54s; without `run_in_background`, the UI serializes foreground tool calls and wall-clock ≈ sum(reviewers) ≈ 112s. Same-message foreground tool calls render and complete in dispatch order — that is sequential in practice. Background mode is the only reliable way to get genuine parallelism in this harness.

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

2. **Fable — `Task` tool with `run_in_background: true`**, `subagent_type: "general-purpose"`, `model: "fable"`, with the entire adversarial review prompt as the `prompt` argument. Returns an agent ID immediately; the subagent runs concurrently with the two `Bash` reviewers.

3. **Gemini — `Bash` tool with `run_in_background: true`** (not `Skill`):

   ```bash
   agy --sandbox --print-timeout 10m -p "Read the file /tmp/multi-review-prompt-<random>.txt in full and perform the adversarial code review it describes. Use only read-only reasoning over the inlined diff; do not edit, write, or run shell commands. Output ONLY the JSON it specifies, nothing else."
   ```

   Write the FULL adversarial prompt (with the diff already inlined — identical to what Codex/Fable get) to a temp file first (`Write` tool to `/tmp/multi-review-prompt-$RANDOM.txt`), then point `agy` at it by absolute path. Key reasons for the file-read form (not `agy -p "<whole prompt>"`):
   - `agy -p` takes the prompt as a flag **argument**, not stdin (`agy -p < file` errors with `flag needs an argument`). Inlining a real PR diff as the argument would blow past shell ARG_MAX (~1MB on macOS) and trip the harness's command-classification heuristics on the `"$(cat …)"` substitution. Pointing `agy` at the file sidesteps both.
   - The diff lives inside the file, so `agy` reviews from the inlined diff and needs no repo access — the single read of the known prompt file is the only tool call.

   `--sandbox` keeps `agy` in terminal-restricted (read-only) mode — the parity replacement for the old `gemini --approval-mode plan`. **Never** pass `--dangerously-skip-permissions` (it auto-approves writes — the opposite of what a reviewer needs). `--print-timeout 10m` covers slow reviews (default is 5m). Don't pin `--model` — let `agy` use its default so the skill picks up model upgrades automatically.

   **Output parsing:** `agy` sends its language-server startup noise and `E…/I…/W…` log lines to **stderr**; the review answer is the JSON object on **stdout**. In `run_in_background` mode the captured output file is the clean JSON answer (stderr is captured separately) — empirically just the JSON. Still, defensively parse the JSON object out of the captured output and ignore any stray log lines (the retry-once-on-non-JSON rule below applies if the parse fails).

After the message returns, the model receives three task IDs (one per reviewer). Wait for the three `<task-notification>` events to fire. Do NOT poll the output files manually — read each output file ONLY after its completion notification arrives. Once all three notifications land, parse JSON from each output file and proceed to the merge step below.

Retry-once-on-non-JSON: if any reviewer's output isn't parseable JSON, re-issue that one call (alone, also `run_in_background: true`). If it fails twice, proceed with the survivors and note the gap.

### Adversarial review prompt

```
<role>You are performing an adversarial code review. Break confidence in the change, do not validate it.</role>
<task>Review the diff provided below. The full diff is inlined here — review from it directly. For any additional context-gathering, use ONLY read-only tools available to you (read-file / glob / grep); do NOT spawn other subagents, and do NOT edit, write, or commit.</task>
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
gap:       none | Codex | Fable | Gemini | <multiple, comma-separated>
```

`to ask == 0` → report clean, stop.

## Write findings + plannotator review

`/tmp/multi-review-questions-$RANDOM.md`, severity desc:

```markdown
# multi-review findings — <branch> vs <base>

## 1. <title>

- severity: high
- reviewers: Codex+Fable+Gemini
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

reviewers:        Codex+Fable+Gemini | Codex+Fable | Codex+Gemini | Fable+Gemini | Codex only | Fable only | Gemini only | none
discarded:        count (low-signal + FPs)
submodule notes:  pointer changes flagged in Step 0 (not reviewed inline)
pre-review HEAD:  <sha>
```

Any `⚠` → don't say "ready".
