# Claude Skills

Shared Claude Code skills for planning, code review, and documentation.

## Workflow: From Idea to Implementation

```
/brainstorm [topic]
    │
    ├── Phase 1: Understand — gather context, ask questions one at a time
    ├── Phase 2: Explore — propose 2-3 approaches with trade-offs
    ├── Phase 3: Design — present design in sections, validate each
    ├── Phase 4: Plan — enter plan mode, review via plannotator
    │
    └── Phase 5: Execute
            ├── Start now — implement task by task
            └── Ralphex plan — autonomous execution via ralphex CLI
```

Start any feature, refactor, or investigation with `/brainstorm`. It walks through collaborative discovery, produces a validated design, then enters plan mode where [plannotator](https://github.com/backnotprop/plannotator) opens a visual UI for annotation and approval. After approval, either implement manually or hand off to [ralphex](https://github.com/umputun/ralphex) for autonomous execution.

## Skills

### [`brainstorm`](plugin/skills/brainstorm/SKILL.md)

The main planning skill. Conversational dialogue that turns ideas into validated designs with structured plan output.

```
/brainstorm add webhook support to our API
```

### [`ralph-review`](plugin/skills/ralph-review/SKILL.md)

Automatic pre-PR iterative review pipeline modeled on umputun's 4-stage flow. Every phase passes findings to a fresh fixer subagent (verify → baseline → fix → validate → commit) so the orchestrator never reads code or runs tests itself. Severity tagging (`CRITICAL/MAJOR/MINOR`) drives codex's minor-only early-exit; a `/tmp/ralphex-progress-<branch>.txt` scratchpad threads context across phases.

1. **Review phase 1** — 5 parallel agents (quality, implementation, testing, simplification, documentation); iters 2+ narrow to 2 critical-only agents; loop ≤5.
2. **Review phase 2** — code smells single pass.
3. **Review phase 3** — codex external review (background, severity-based exit, ≤10 iterations).
4. **Review phase 4** — critical-only safety net (single pass).

```
/ralph-review           # diff against main
/ralph-review develop   # diff against develop
```

Requires the `codex` CLI on `PATH` for review phase 3 (skipped gracefully if missing).

### [`github-pr`](plugin/skills/github-pr/SKILL.md)

Copilot-aware GitHub PR review loop. Polls for Copilot reviews (with required re-request between rounds), resolves resolved threads, and iterates until the PR is clean. Wraps `gh` CLI + GraphQL.

```
/github-pr 42
```

### [`multi-review`](plugin/skills/multi-review/SKILL.md)

Three-reviewer adversarial code review against a base branch. Runs Codex (via direct `codex exec`), a fresh Opus subagent (via `Task`), and Gemini (via the `gemini` CLI) in parallel, merges findings, and presents them as a single plannotator pass before applying any fix in one commit.

```
/multi-review
```

Prerequisites:
- `thinking-tools` plugin installed (provides the model-invocable `ask-codex` Skill).
- `plannotator` binary on PATH — the skill invokes `plannotator annotate` via Bash (the bundled `/plannotator-annotate` slash command has `disable-model-invocation: true` and is user-only by design).
- `gemini` CLI on PATH (auth via `GEMINI_API_KEY` env or `gcloud auth application-default login`).

### [`ask-gemini`](plugin/skills/ask-gemini/SKILL.md)

Thin wrapper around the local `gemini` CLI for second-opinion runs on diffs or quick adversarial reviews. Best used standalone when you want a focused Gemini pass outside `multi-review`.

```
ask gemini about this diff
```

### [`md-to-pdf`](plugin/skills/md-to-pdf/SKILL.md)

Convert Markdown files to clean A4 PDFs with Mermaid diagram support via pre-render and SVG inlining.

```
/md-to-pdf docs/architecture.md
```

### [`docx`](plugin/skills/docx/SKILL.md)

Read, edit, and export Microsoft Word documents. Supports text replacement, table cell editing, and PDF export.

```
/docx read contract.docx
/docx edit contract.docx '{"old text": "new text"}'
```

### [`notion-annotate`](plugin/skills/notion-annotate/SKILL.md)

Remote-friendly alternative to plannotator. Pushes a markdown file to Notion so the user can read and comment on it from any device, then pulls comments back as git-review style feedback.

```
/notion-annotate push docs/plan.md
/notion-annotate pull docs/plan.md
```

### [`skill-vetting`](plugin/skills/skill-vetting/SKILL.md)

Security vetting for third-party skills. Downloads to /tmp, runs automated scanner, manual code review, utility assessment.

```
/skill-vetting https://github.com/someone/some-skill
```

### [`skill-writer`](plugin/skills/skill-writer/SKILL.md)

Create and improve Claude Code skills following official best practices and Agent Skills spec.

```
/skill-writer create a new review skill
```

## Companion Plugins

These plugins extend the workflow with additional capabilities:

| Plugin | What it adds |
|--------|-------------|
| [backnotprop/plannotator](https://github.com/backnotprop/plannotator) | Visual plan review and annotation UI in browser |
| [umputun/ralphex](https://github.com/umputun/ralphex) | Autonomous plan execution + `ralphex-plan` skill for plan creation |
| [umputun/cc-thingz](https://github.com/umputun/cc-thingz) | `ask-codex` (GPT-5 second opinion), `dialectic` (opposing agents), `root-cause-investigator` (5-Why) |
| [umputun/revdiff](https://github.com/umputun/revdiff) | TUI for reviewing diffs, files, and documents with inline annotations — outputs structured results for AI agents |

```bash
/plugin marketplace add backnotprop/plannotator
/plugin install plannotator@plannotator --scope user

/plugin marketplace add umputun/ralphex
/plugin install ralphex --scope user

/plugin marketplace add umputun/cc-thingz
/plugin install thinking-tools --scope user

/plugin marketplace add umputun/revdiff
/plugin install revdiff@umputun-revdiff --scope user
brew install umputun/apps/revdiff
```

## Installation

```bash
/plugin marketplace add fitz123/claude-skills
/plugin install claude-skills --scope user
```

Or test locally:

```bash
claude --plugin-dir /path/to/claude-skills
```

## License

MIT
