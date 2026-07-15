---
name: ask-gemini
description: Consult Google Gemini for investigation, debugging, or code review. Use when user explicitly asks to "ask gemini", "check with gemini", or "gemini review". Good for second-opinion runs on diffs and quick adversarial reviews. Runs in read-only sandbox mode.
argument-hint: "<question or prompt>"
allowed-tools:
  - Bash(agy:*)
  - Read
  - Write(/tmp/*)
  - Grep
  - Glob
---

# Ask Gemini

Consult Google Gemini as a second-opinion reviewer for investigation, debugging, or code review tasks. Gemini runs locally via the Antigravity `agy` CLI in read-only `--sandbox` mode, so it can read project files but cannot write or execute shell commands. Use it standalone for a quick sanity-check on a hypothesis or a focused adversarial review.

> **`agy` is the replacement for the old `gemini` CLI.** Google discontinued the free "Gemini Code Assist for individuals" OAuth tier in the `gemini` CLI (it now errors with `IneligibleTierError` / "migrate to the Antigravity suite") and routes individuals to the Antigravity CLI. `agy` runs the same Gemini models. See the Authentication and Troubleshooting sections for setup.

## Activation Triggers

**Explicit:**
- "ask gemini", "check with gemini", "gemini review"
- "what does gemini think", "get gemini opinion"
- "consult gemini", "run gemini on this"

**Automatic (last resort — stuck detection):**
- 4+ failed attempts at the same bug fix or investigation
- completely out of ideas, all reasonable approaches exhausted
- going in circles with no progress despite multiple different strategies

## Workflow

### Step 1: Check Availability

Run `which agy` to verify the CLI is installed. On macOS the typical path is `/opt/homebrew/bin/agy` (installed via `brew install --cask antigravity-cli`). If the command is not found, inform the user that the Antigravity `agy` CLI is missing and stop — do not attempt to fall back to another model silently.

### Step 2: Build Context

Gather context from the current conversation:

1. **What's the problem/question** — summarize in 2-3 sentences
2. **What we know** — relevant files, error messages, behavior observed vs expected
3. **What we tried** — approaches attempted and why they failed (if applicable)
4. **Specific question** — what exactly Gemini should analyze or answer

Cite file paths and line references rather than dumping entire files. `agy` has read-only filesystem access in `--sandbox` mode and can read what it needs.

### Step 3: Construct Prompt

Build a focused prompt. Do NOT dump entire files — `agy` can read them itself via its read tools. Provide file paths and line references so it knows where to look.

**Template for investigation/debug:**

```
# [Investigation/Debug] Request

## Problem
[2-3 sentence description]

## Context
- Files: [path/to/file.go:lineNumber, ...]
- Observed: [what's happening]
- Expected: [what should happen]

## What We Tried
[List approaches and outcomes, or "First consultation" if fresh question]

## Question
[Specific, focused question for Gemini to answer]

Provide:
1. Root cause analysis (if debugging)
2. Concrete recommendation with file:line references
3. Why previous approaches failed (if applicable)

Keep response focused and actionable.
```

**Template for code review (adversarial):**

When asked for an adversarial code review (or when invoked by `multi-review`), use the strict-JSON contract — see the "Use with multi-review's adversarial contract" section below for the full prompt shape.

### Step 4: Invoke agy

Primary invocation (read-only `--sandbox` mode):

```bash
agy --sandbox --print-timeout 10m -p "<prompt>"
```

`--sandbox` enables terminal restrictions: the model can read files via its built-in tools but cannot write or run shell commands. This is the correct mode for review and investigation — confirm against `agy --help` if behavior diverges. **Never** pass `--dangerously-skip-permissions` (it auto-approves writes — the opposite of a read-only reviewer). `--print-timeout 10m` covers slow runs (default 5m).

**`-p` takes the prompt as an argument, not stdin** (`agy -p < file` errors with `flag needs an argument`). For prompts that embed large diffs or multi-file context (approaching macOS `ARG_MAX` ~1MB), use the `Write` tool to save the full prompt to `/tmp/ask-gemini-prompt-<random>.txt` (the skill's `allowed-tools` grants `Write(/tmp/*)` for exactly this), then have `agy` read it instead of passing it as an argument:

```bash
agy --sandbox --print-timeout 10m -p "Read the file /tmp/ask-gemini-prompt-<random>.txt in full and answer the request it contains. <one-line restatement of the ask>."
```

This sidesteps both `ARG_MAX` and the harness's command-classification heuristics on `"$(cat …)"` substitutions. (`Bash(agy:*)` alone can't create the file — that's why `Write` is in `allowed-tools`.)

**Don't pin `--model`** — always use `agy`'s default. As Antigravity's defaults evolve, this skill picks up the upgrade automatically. JSON-strict callers (`multi-review`) absorb occasional default-model misses via their own retry-once-on-non-JSON policy.

### Step 5: Process Response

`agy` sends its language-server startup noise and `E…/I…/W…` log lines to **stderr**; the substantive answer is on **stdout**. In `run_in_background` mode the captured output file is the clean stdout answer (stderr is captured separately) — empirically just the answer. Still, defensively parse the meaningful content out in case streams are ever merged.

For **investigation/debug** responses (unstructured prose): present cleaned, formatted output and add your assessment.

For **strict-JSON** responses (when invoked by `multi-review` or any caller requesting the adversarial contract): expect raw JSON. If it arrives wrapped in a ```json fence or preceded by preamble, the caller (e.g. `multi-review`) handles the retry-once-on-non-JSON path; do not silently re-parse here. Surface what `agy` returned and let the caller decide whether to retry.

**CRITICAL: After presenting findings, STOP. Do not apply fixes, do not touch files, do not start implementing suggestions. Gemini's output is input for discussion, not an automatic work order.**

## Use with multi-review's adversarial contract

`multi-review` invokes the `agy` CLI directly so all three reviewers can be launched as same-message tool calls without an extra `Skill` round-trip. `ask-gemini` remains the standalone interactive wrapper for the same CLI and adversarial-review prompt shape, so callers outside `multi-review` can still reuse that contract when they want a focused Gemini-only pass.

**Read-only tool constraint:** `--sandbox` is a terminal restriction (no shell/git execution) and `agy` reads files freely. Whether `--sandbox` also blocks write-capable tools at the tool layer is not verified here, so treat "no writes" as **prompt-enforced** rather than a hard guarantee. Always constrain the prompt's tool routing for adversarial review: "use ONLY read-only tools available to you (read-file / glob / grep); do NOT spawn other subagents, and do NOT edit, write, or commit." The `multi-review` prompt template includes this constraint by design — if you're calling `ask-gemini` from elsewhere with the adversarial JSON contract, include the same constraint.

**Inline the diff (don't reference a shell command):** `agy` in `--sandbox` mode cannot run shell, so a prompt that says "Review `git diff base...HEAD`" fails — `agy` has no way to run git. The caller (e.g. `multi-review`'s orchestrator) must resolve the diff via shell first and inline it inside the prompt body (typically inside a `<diff>...</diff>` block) — or write the full prompt+diff to a temp file that `agy` reads. Codex and Fable tolerate either form; `agy` requires the inlined-diff (or file-read) form.

The contract requires **strict JSON** with this shape:

```json
{
  "verdict": "approve" | "needs-attention",
  "summary": "<one-line summary>",
  "findings": [
    {
      "severity": "critical" | "high" | "medium" | "low",
      "title": "<short title>",
      "body": "<what can go wrong, why, impact>",
      "file": "<path>",
      "line_start": <int>,
      "line_end": <int>,
      "confidence": 0.0,
      "recommendation": "<concrete fix>"
    }
  ],
  "next_steps": ["<follow-up actions>"]
}
```

The merge/triage logic, JSON-retry policy, and gap-reporting all live in `multi-review`; `ask-gemini` is intentionally thin.

## agy-specific gotchas

- **Must run OUTSIDE Claude Code's Bash sandbox.** `agy` reads its OAuth token from the **macOS Keychain** (not a file; `~/.gemini/` holds only config, logs, and the installation id), and Claude Code's Bash sandbox blocks the `securityd` Mach lookup. A sandboxed `agy` fails with `error getting token source: You are not logged into Antigravity`. Fix: add `"agy:*"` to `sandbox.excludedCommands` in Claude Code settings (same as the existing `codex:*` entry) so `agy` runs unsandboxed and can reach the Keychain.
- **Large-prompt handling**: `agy -p` takes the prompt as an argument (not stdin). For prompts approaching `ARG_MAX` (~1MB on macOS) — embedded diffs, multi-file context — write the prompt to a temp file and have `agy` read it (see Step 4).
- **`--sandbox` semantics**: terminal-restricted, read-only — the model can read files via built-in tools but cannot write or execute shell. This is the parity replacement for the old `gemini --approval-mode plan`. **For this skill, `--sandbox` is the default.**
- **Default model selection**: invoking `agy` without `--model` uses the CLI default — which evolves as Antigravity updates the CLI. This skill intentionally does NOT pin a model, so it picks up upgrades automatically. The retry-once-on-non-JSON policy in `multi-review` absorbs occasional default-model misses.

## Important Rules

- **Read-only always** — Gemini analyzes, we implement. Default invocation uses `--sandbox`; never use `--dangerously-skip-permissions`.
- **Don't duplicate files** — `agy` has read-only filesystem access. Provide paths, not content.
- **Focused prompts** — specific questions get better answers than broad "review everything".
- **One question at a time** — if multiple concerns, run separate Gemini queries.
- **Critical thinking** — Gemini can be wrong. Evaluate its suggestions before implementing.

## When NOT to Use

- Simple questions you already know the answer to
- Tasks where the solution is clear and just needs implementation
- File searches or codebase navigation (use Grep/Glob directly instead)

## Troubleshooting

- **agy not found**: `which agy` — install via `brew install --cask antigravity-cli` (links the `antigravity` binary to `agy`). The separate `antigravity` cask is the GUI IDE and is NOT required for this skill.
- **`You are not logged into Antigravity`**: either (a) you haven't logged the CLI in — run bare `agy` once in a normal (non-sandboxed) shell and complete Google Sign-In; or (b) `agy` is running inside Claude Code's Bash sandbox, which can't read the Keychain — add `"agy:*"` to `sandbox.excludedCommands` (see gotchas above).
- **`IneligibleTierError` / "migrate to the Antigravity suite"**: that's the old `gemini` CLI's dead individuals tier. Use `agy`, not `gemini`.
- **Empty/garbled output**: the answer is on stdout; `agy`'s log noise is on stderr. If the prompt was huge, switch to the file-read form (Step 4) — `-p` may have hit `ARG_MAX`.
- **Non-JSON when JSON was required**: caller handles retry; if it persists, tighten the prompt's output contract. (Don't reach for `--model` to "fix" reliability — keep the skill default-model-driven so CLI upgrades carry through.)
