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

### [`brainstorm`](skills/brainstorm/SKILL.md)

The main planning skill. Conversational dialogue that turns ideas into validated designs with structured plan output.

```
/brainstorm add webhook support to our API
```

### [`ralph-review`](skills/ralph-review/SKILL.md)

Multi-agent code review pipeline. 5 specialized agents (quality, implementation, testing, simplification, documentation) review changes in parallel, verify findings, fix confirmed issues, then iterate with codex cross-review.

```
/ralph-review           # diff against main
/ralph-review develop   # diff against develop
```

### [`md-to-pdf`](skills/md-to-pdf/SKILL.md)

Convert Markdown files to clean A4 PDFs with Mermaid diagram support via pre-render and SVG inlining.

```
/md-to-pdf docs/architecture.md
```

### [`docx`](skills/docx/SKILL.md)

Read, edit, and export Microsoft Word documents. Supports text replacement, table cell editing, and PDF export.

```
/docx read contract.docx
/docx edit contract.docx '{"old text": "new text"}'
```

### [`skill-vetting`](skills/skill-vetting/SKILL.md)

Security vetting for third-party skills. Downloads to /tmp, runs automated scanner, manual code review, utility assessment.

```
/skill-vetting https://github.com/someone/some-skill
```

### [`skill-writer`](skills/skill-writer/SKILL.md)

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

```bash
/plugin marketplace add backnotprop/plannotator
/plugin install plannotator@plannotator --scope user

/plugin marketplace add umputun/ralphex
/plugin install ralphex --scope user

/plugin marketplace add umputun/cc-thingz
/plugin install thinking-tools --scope user
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
