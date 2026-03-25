# Claude Skills

Shared Claude Code skills for planning, code review, and documentation.

## Skills

| Skill | Description |
|-------|-------------|
| `plan` | Decision-complete planning pipeline with dual-perspective validation |
| `ralphex-plan` | Create plans for ralphex automated code review |
| `ralph-review` | Parallel multi-agent code review (prompt-only) |
| `md-to-pdf` | Convert Markdown to clean A4 PDFs with Mermaid support |
| `docx` | Read, edit, and export Microsoft Word documents |
| `skill-vetting` | Security vetting for third-party skills |
| `skill-writer` | Skill creation and improvement |

## Companion Plugins

From [umputun/cc-thingz](https://github.com/umputun/cc-thingz):

```bash
/plugin marketplace add umputun/cc-thingz
/plugin install brainstorm --scope user
/plugin install thinking-tools --scope user
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
