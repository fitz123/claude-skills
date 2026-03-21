---
name: codex
description: Gets second opinion from OpenAI Codex CLI with xhigh reasoning. Use for solution validation, architecture review, or independent problem analysis.
allowed-tools:
  - Bash(codex:*)
---

# Codex Second Opinion

Independent analysis using OpenAI Codex CLI with extreme reasoning effort.

## Command

```bash
codex exec -m gpt-5.3-codex -c model_reasoning_effort=xhigh -o /tmp/codex_out.md \
  "CONTEXT: ...
QUESTION: ...
PROVIDE: ..."
```

Then read the output:
```bash
cat /tmp/codex_out.md
```

**Required flags:**

- `-m gpt-5.3-codex` - model with xhigh support
- `-c model_reasoning_effort=xhigh` - extreme reasoning
- `-o /tmp/codex_out.md` - capture full output (prevents truncation)

## Prompt Structure

Use structured prompts for xhigh efficiency:

```
CONTEXT: [situation/domain]
QUESTION: [specific ask]
CONSTRAINTS: [requirements] (optional)
PROVIDE: [expected format]
```

## Workflow

1. Structure prompt with CONTEXT/QUESTION/PROVIDE
2. Run with `-o` flag
3. Read output with `cat`
4. Present findings to user

## Flags Reference

| Flag | Purpose |
|------|---------|
| `-C` | Working directory for code context |
| `-i` | Attach images |
| `--full-auto` | Auto-approve with sandbox |
