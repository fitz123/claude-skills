---
name: linting-markdown
description: Validates markdown files with markdownlint-cli2. Use when checking markdown syntax, fixing lint errors, or ensuring consistent formatting.
allowed-tools:
  - Bash(npx markdownlint-cli2:*)
---

# Markdown Lint

Validate and fix markdown files using markdownlint-cli2.

## Quick Start

```bash
npx markdownlint-cli2 "*.md"
```

With specific files:
```bash
npx markdownlint-cli2 README.md docs/*.md
```

## Workflow

```
Validation Progress:
- [ ] Run markdownlint-cli2 on target files
- [ ] Group errors by file and rule
- [ ] Fix structural issues (blank lines, headings)
- [ ] Update .markdownlint-cli2.yaml for intentional exceptions
- [ ] Re-run to confirm zero errors
```

## Fixing Common Errors

| Rule | Issue | Fix |
|------|-------|-----|
| MD022 | Missing blank line around heading | Add blank line before/after |
| MD032 | Missing blank line around list | Add blank line before/after |
| MD009 | Trailing spaces | Remove trailing whitespace |
| MD047 | Missing final newline | Add newline at EOF |
| MD036 | Emphasis as heading | Use heading or disable rule |
| MD013 | Line too long | Wrap or disable for prose |

## Config File

Create `.markdownlint-cli2.yaml` in project root:

```yaml
config:
  MD013: false  # line length - impractical for prose
  MD036: false  # emphasis as heading - if intentional
```

## Best Practices

1. Fix structural issues (MD022, MD032) by editing files
2. Disable rules only when intentional (prose line length, styled emphasis)
3. Keep config in project root for consistency
4. Run validation after fixes to confirm resolution
