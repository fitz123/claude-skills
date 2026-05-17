---
name: ask-gemini
description: Consult Google Gemini for investigation, debugging, or code review. Use when user explicitly asks to "ask gemini", "check with gemini", "gemini review", or as a parallel reviewer in multi-review. Good for second-opinion runs on diffs and quick adversarial reviews. Runs in read-only plan mode.
argument-hint: "<question or prompt>"
allowed-tools:
  - Bash(gemini:*)
  - Read
  - Grep
  - Glob
---

# Ask Gemini

Consult Google Gemini as a second-opinion reviewer for investigation, debugging, or code review tasks. Gemini runs locally via the homebrew `gemini` CLI in read-only `plan` mode, so it can read project files but cannot write or execute. Use it standalone for a quick sanity-check on a hypothesis, or as one of the parallel reviewers in `multi-review`.

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

Run `which gemini` to verify the CLI is installed. On macOS the typical path is `/opt/homebrew/bin/gemini`. If the command is not found, inform the user that the Gemini CLI is missing and stop — do not attempt to fall back to another model silently.

### Step 2: Build Context

Gather context from the current conversation:

1. **What's the problem/question** — summarize in 2-3 sentences
2. **What we know** — relevant files, error messages, behavior observed vs expected
3. **What we tried** — approaches attempted and why they failed (if applicable)
4. **Specific question** — what exactly Gemini should analyze or answer

Cite file paths and line references rather than dumping entire files. Gemini has filesystem access in `plan` mode and can read what it needs.

### Step 3: Construct Prompt

Build a focused prompt. Do NOT dump entire files — Gemini can read them itself via its filesystem tools in plan mode. Provide file paths and line references so it knows where to look.

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

When asked for an adversarial code review (or when invoked by `multi-review`), use the strict-JSON contract — see the "Use as multi-review reviewer" section below for the full prompt shape.

### Step 4: Invoke Gemini

Primary invocation (read-only `plan` mode):

```bash
gemini -p "<prompt>" --approval-mode plan
```

`--approval-mode plan` is read-only: the model can read files via its built-in filesystem tools but cannot write or execute. This is the correct mode for review and investigation — confirm against `gemini --help` if behavior diverges.

For prompts that approach macOS shell `ARG_MAX` (~256KB) — typically anything that embeds large diffs or multi-file context — pipe via stdin instead of `-p`:

```bash
echo "<prompt>" | gemini --approval-mode plan
```

Optional flags:
- `-m <model>` — pin a specific model. Without `-m`, Gemini selects a default. For JSON-strict outputs in `multi-review`, pinning a pro-tier model improves reliability (the caller retries once on non-JSON, so occasional misses are tolerated).
- `--output-format json` — structured CLI output wrapper; orthogonal to the prompt-level JSON contract. Usually not needed.

### Step 5: Process Response

Gemini's reply may include a brief preamble or interleaved tool-use lines before the substantive answer; parse the meaningful content out.

For **investigation/debug** responses (unstructured prose): present cleaned, formatted output and add your assessment.

For **strict-JSON** responses (when invoked by `multi-review` or any caller requesting the adversarial contract): expect raw JSON. If it arrives wrapped in a ```json fence or preceded by preamble, the caller (e.g. `multi-review`) handles the retry-once-on-non-JSON path; do not silently re-parse here. Surface what Gemini returned and let the caller decide whether to retry.

**CRITICAL: After presenting findings, STOP. Do not apply fixes, do not touch files, do not start implementing suggestions. Gemini's output is input for discussion, not an automatic work order.**

## Use as multi-review reviewer

`ask-gemini` participates in `multi-review`'s parallel-reviewer flow as the third reviewer alongside Codex (via `thinking-tools:ask-codex`) and a fresh Opus subagent (via `Task`). The caller passes the canonical adversarial-review prompt from `multi-review/SKILL.md`; this skill's job is to invoke the Gemini CLI and surface the raw response.

**Plan-mode subagent constraint (important):** `--approval-mode plan` allows only a fixed set of tools — read-only filesystem access (`read_file`, `glob`, `grep_search`) plus two default-allowed subagents (`codebase_investigator`, `cli_help`). Any OTHER subagent the model tries to route through (`invoke_agent <name>`) is denied by the policy engine and the run aborts. The caller's prompt **must** constrain Gemini's tool routing accordingly: e.g. "use ONLY the `codebase_investigator` subagent or direct read tools; do NOT invoke other subagents." The `multi-review` prompt template includes this constraint by design — if you're calling `ask-gemini` from elsewhere with the adversarial JSON contract, include the same constraint.

**Inline the diff (don't reference a shell command):** Gemini in plan mode cannot execute shell commands, so a prompt that says "Review `git diff base...HEAD`" fails — Gemini has no way to see the diff. The caller (e.g. `multi-review`'s orchestrator) must resolve the diff via shell first and inline it inside the prompt body (typically inside a `<diff>...</diff>` block). Codex and Opus tolerate either form; Gemini requires the inline form.

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

Note: at the time of writing, `multi-review` does not yet exist in this plugin — it lands in the same PR (Tasks 2 and 3). This is a forward reference. The merge/triage logic, JSON-retry policy, and gap-reporting all live in `multi-review`; `ask-gemini` is intentionally thin.

## Gemini-specific gotchas

- **Large-prompt handling**: prefer stdin (`echo "<prompt>" | gemini --approval-mode plan`) over `-p "<prompt>"` for prompts approaching shell `ARG_MAX` (~256KB on macOS). Embedded diffs and multi-file context blow past this threshold quickly.
- **`--approval-mode plan` semantics**: plan mode is read-only filesystem (no write, no execute) AND restricts subagent invocations to a fixed allowlist (`codebase_investigator`, `cli_help`). The model can still read files via built-in tools. The full mode set is `default | auto_edit | yolo | plan`. Plan is the documented headless mode for code review; in non-interactive runs, `default` also works fine because Gemini's policy engine treats `ask_user` as `deny` when there's no TTY. `yolo` works too but lifts all safety nets. **For this skill, `plan` is the default** — but be aware of the subagent allowlist constraint above.
- **Authentication**: Gemini CLI checks `GEMINI_API_KEY` env var **or** `gcloud auth application-default login` (whichever the homebrew build wires up first). Document both paths and let the user pick — neither is privileged in this skill.
- **Default model selection**: invoking `gemini` without `-m` selects a default model that may shift over time. For JSON-strict outputs in `multi-review`, pin a specific pro-tier model via `-m <name>` if reliability matters. The retry-once-on-non-JSON policy in `multi-review` absorbs occasional default-model misses, so pinning is recommended-not-required.

## Important Rules

- **Read-only always** — Gemini analyzes, we implement. Default invocation uses `--approval-mode plan`; switching modes requires explicit prompt-level constraints and a justification (e.g. needing to invoke a subagent outside plan-mode's allowlist).
- **Don't duplicate files** — Gemini has filesystem access in plan mode. Provide paths, not content.
- **Focused prompts** — specific questions get better answers than broad "review everything".
- **One question at a time** — if multiple concerns, run separate Gemini queries.
- **Critical thinking** — Gemini can be wrong. Evaluate its suggestions before implementing.

## When NOT to Use

- Simple questions you already know the answer to
- Tasks where the solution is clear and just needs implementation
- File searches or codebase navigation (use Grep/Glob directly instead)

## Troubleshooting

- **Gemini not found**: `which gemini` — install via `brew install gemini-cli` (or the project's documented install path).
- **Authentication errors**: set `GEMINI_API_KEY` env var, or run `gcloud auth application-default login`. Check `gemini --help` for the CLI's auth subcommand if it has one.
- **Empty/garbled output**: re-run with stdin instead of `-p` (prompt may have hit `ARG_MAX`).
- **Non-JSON when JSON was required**: caller handles retry; if it persists, tighten the prompt's output contract or pin a pro-tier model via `-m`.
