# Claude Skills

Shared Claude Code skills for planning, code review, documentation, and task management.

## Skills

| Skill | Description |
|-------|-------------|
| `plan` | Decision-complete planning pipeline with dual-perspective validation |
| `ralphex-plan` | Create plans for ralphex automated code review |
| `ralphex` | Multi-agent iterative review pipeline via ralphex |
| `md-to-pdf` | Convert Markdown to clean A4 PDFs with Mermaid support |
| `knowledge-loader` | Load documents into structured, indexed knowledge bases |
| `skill-vetting` | Security vetting for third-party skills |
| `systems-architect` | Systems analysis and architecture knowledge base |
| `beads-tasks` | Task management via Beads CLI |

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
