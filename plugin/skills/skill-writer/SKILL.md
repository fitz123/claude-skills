---
name: skill-writer
description: Creates well-structured Claude Code skills following official best practices. Use when writing new skills, improving existing skills, or reviewing skill quality.
allowed-tools:
  - Read(*)
  - Write(*)
  - Bash(mkdir:*)
  - WebFetch(*)
---

# Skill Writer

**Last updated**: 2026-02-18

Creates Claude Code skills following the [official docs](https://code.claude.com/docs/en/skills) and [Agent Skills spec](https://agentskills.io/specification).

## Self-Update Check

**On every invocation**, before writing any skill:

1. Compare today's date against "Last updated" above
2. If **>30 days old**: fetch the official docs and compare against this skill before proceeding
   - `WebFetch https://code.claude.com/docs/en/skills` — check for new frontmatter fields, features, or changed conventions
   - Update this SKILL.md if anything changed, bump the "Last updated" date
   - Then proceed with the user's request
3. If **<=30 days**: proceed normally

## Frontmatter

```yaml
---
name: fix-issue                # lowercase, hyphens, max 64, must match directory name
description: Fixes GitHub issues by number. Use when resolving issues or applying bug fixes.
argument-hint: "[issue-number]" # optional, shown in autocomplete
disable-model-invocation: true  # optional, manual /name only
allowed-tools:                  # optional
  - Bash(curl:*)
  - Read(*)
---
```

All fields optional. Only `description` is recommended.

| Field | Purpose |
|-------|---------|
| `name` | Display name. Defaults to directory name. Lowercase + hyphens, max 64 chars. **Must match parent directory.** |
| `description` | WHAT it does + WHEN to use it. Max 1024 chars. Third person ("Processes files", not "I process"). |
| `argument-hint` | Autocomplete hint, e.g. `[issue-number]` or `[filename] [format]` |
| `disable-model-invocation` | `true` = only user can invoke via `/name`. Use for side-effect workflows. |
| `user-invocable` | `false` = hidden from `/` menu. Use for background knowledge Claude loads automatically. |
| `allowed-tools` | Tools Claude can use without permission prompts when skill is active. |
| `model` | Model override when skill is active. |
| `context` | `fork` = run in isolated subagent (no conversation history). |
| `agent` | Subagent type when `context: fork`. Options: `Explore`, `Plan`, `general-purpose`, or custom agent name. |
| `hooks` | Lifecycle hooks scoped to this skill. Same format as settings hooks. |

### Invocation Control

| Frontmatter | User invokes | Claude invokes |
|-------------|:---:|:---:|
| (default) | yes | yes |
| `disable-model-invocation: true` | yes | no |
| `user-invocable: false` | no | yes |

### Skill Types

**Reference** — conventions, patterns, domain knowledge. Runs inline, Claude applies to current work.

**Task** — step-by-step instructions (deploy, commit, sync). Often paired with `disable-model-invocation: true`.

## String Substitutions & Dynamic Context Injection

Both features use live syntax that the skill loader processes before Claude sees content. Documenting them inline would corrupt this skill. See [REFERENCE.md](REFERENCE.md) for full details on:
- **String substitutions** — passing arguments to skills (positional and named)
- **Dynamic context injection** — embedding shell command output in skill content

## Core Principles

### 1. Concise is Key

Only add context Claude doesn't already have:
- "Does Claude need this explanation?"
- "Can I assume Claude knows this?"

### 2. Degrees of Freedom

| Freedom | When | Example |
|---------|------|---------|
| High | Multiple valid approaches | Code review guidelines |
| Medium | Preferred pattern exists | Template with parameters |
| Low | Fragile/critical ops | Exact API calls, migration scripts |

### 3. Progressive Disclosure

Keep SKILL.md under 500 lines. Split into reference files:

```
skill-name/
├── SKILL.md              # Overview, workflow (required)
├── references/           # Detailed docs (loaded when needed)
├── assets/               # Templates, data files
└── scripts/              # Executable utilities
```

Reference one level deep only (SKILL.md -> files, not files -> files).

## Skill Template

```markdown
---
name: deploy-app
description: Deploys the application to production. Use when releasing or pushing to prod.
disable-model-invocation: true
allowed-tools:
  - Bash(*)
---

# Deploy App

Brief intro (1-2 sentences max).

## Quick Start

Minimal working example.

## Core Operations

### Operation 1
\`\`\`bash
command example
\`\`\`

## Workflows

\`\`\`
Progress:
- [ ] Step 1: Description
- [ ] Step 2: Description
\`\`\`

## Troubleshooting

Common issues and solutions.
```

## Anti-Patterns

1. **Over-explaining** — don't explain what Claude already knows
2. **Too many options** — one default, mention alternatives only when necessary
3. **Vague names** — avoid `helper`, `utils`, `tools`; use verb-noun (`fix-issue`, `deploy-app`)
4. **Inconsistent terminology** — pick one term, use throughout

## Checklist

- [ ] `name` matches parent directory name
- [ ] Description: third-person, WHAT + WHEN, max 1024 chars
- [ ] SKILL.md under 500 lines
- [ ] References one level deep only
- [ ] Concrete examples, not abstract explanations
- [ ] Clear workflow checklists for multi-step tasks
- [ ] `disable-model-invocation: true` if skill has side effects

## Official Documentation

- [Skills guide](https://code.claude.com/docs/en/skills) — canonical reference
- [Agent Skills spec](https://agentskills.io/specification) — open standard
- [Subagents](https://code.claude.com/docs/en/sub-agents) — `context: fork` and skill preloading
- [Hooks](https://code.claude.com/docs/en/hooks) — hooks in skill frontmatter

## Files in This Skill

- [REFERENCE.md](REFERENCE.md) — Dynamic context injection, subagents, hooks, context budget
- [EXAMPLES.md](EXAMPLES.md) — Full skill examples by category
