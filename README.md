# Claude Skills

Shared Claude Code skills for planning, code review, and documentation.

## Skills

| Skill | Description |
|-------|-------------|
| `brainstorm` | Collaborative idea-to-design dialogue, then plan mode with plannotator or ralphex |
| `ralph-review` | Parallel multi-agent code review (prompt-only) |
| `md-to-pdf` | Convert Markdown to clean A4 PDFs with Mermaid support |
| `docx` | Read, edit, and export Microsoft Word documents |
| `skill-vetting` | Security vetting for third-party skills |
| `skill-writer` | Skill creation and improvement |

## Companion Plugins

From [umputun/cc-thingz](https://github.com/umputun/cc-thingz) — `thinking-tools` provides `ask-codex`, `dialectic`, and `root-cause-investigator`:

```bash
/plugin marketplace add umputun/cc-thingz
/plugin install thinking-tools --scope user
```

From [backnotprop/plannotator](https://github.com/backnotprop/plannotator) — visual plan review and annotation:

```bash
/plugin marketplace add backnotprop/plannotator
/plugin install plannotator@plannotator --scope user
```

From [umputun/ralphex](https://github.com/umputun/ralphex):

```bash
/plugin marketplace add umputun/ralphex
/plugin install ralphex --scope user
```

## Installation

Install as a Claude Code plugin:

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
