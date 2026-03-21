# Skill Writer — Reference

## String Substitutions

The skill loader replaces these placeholders before Claude sees the content. You CANNOT document them literally in a SKILL.md — they'll be substituted on load.

| Variable | Description |
|----------|-------------|
| Dollar sign + ARGUMENTS | All args passed when invoking the skill. If not present in content, appended as `ARGUMENTS: <value>`. |
| Dollar sign + ARGUMENTS[N] | Access arg by 0-based index. Also available as shorthand: dollar sign + N (e.g., first arg = dollar sign + 0). |
| Dollar sign + {CLAUDE_SESSION_ID} | Current session ID. Useful for session-specific files or logging. |

### Gotcha

Same as dynamic context injection: if you write a skill that **documents** these variables, the loader replaces them with actual values. Move documentation to a reference file (like this one) and describe them indirectly.

## Dynamic Context Injection

The syntax `!` followed by a backtick-wrapped command (e.g., `` !` ``gh pr diff`` ` ``) runs shell commands **before** skill content is sent to Claude. The command output replaces the placeholder inline.

**IMPORTANT**: This syntax is live — the skill loader executes it on load. You CANNOT include literal examples in a SKILL.md without them being executed. Only use this in skills that actually need runtime data injection.

### How it works

1. Each injection pattern executes immediately (before Claude sees anything)
2. The output replaces the placeholder in the skill content
3. Claude receives the fully-rendered prompt with real data

### Usage pattern

In your SKILL.md, write the injection command inline where you want the output to appear:

```
## Context
- Current branch: <injection: git branch --show-current>
- Recent commits: <injection: git log --oneline -5>
```

Replace `<injection: ...>` with the actual syntax: exclamation mark, backtick, command, backtick.

### Best practice

Pair with `context: fork` so the skill runs in a subagent with injected data and no conversation history overhead.

### Gotcha

If you're writing a **meta-skill** (a skill that documents other skills), you cannot include the injection syntax literally — even inside code fences. The loader scans the raw text before markdown parsing. Move examples to a reference file (like this one) and describe the syntax indirectly.

## Subagent Execution

### context: fork

Runs the skill in an isolated subagent. The skill content becomes the subagent's prompt. No access to conversation history.

```yaml
---
name: pr-summary
context: fork
agent: Explore
---
```

### agent field

Specifies which subagent type to use. Options:
- `Explore` — fast codebase exploration
- `Plan` — architecture planning
- `general-purpose` — default, full tool access
- Custom agent name from `.claude/agents/`

### Skills preloading in subagents

Subagents can preload skills via a `skills` field in their definition:

```yaml
---
name: api-developer
description: Implements API endpoints following team conventions
skills:
  - api-conventions
  - error-handling-patterns
---
```

Full skill content is injected at startup, not just made available for invocation.

## Hooks in Skills

Skills support lifecycle hooks in frontmatter, scoped to the skill's lifetime:

```yaml
---
name: secure-ops
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/security-check.sh"
---
```

The `once` field (boolean): if `true`, runs only once per session then is removed. Available for skills only.

## Context Budget

Skill descriptions are loaded into context at startup so Claude knows what's available. The budget is **2% of the context window** (fallback: 16,000 chars). If you have many skills, some may be excluded. Check with `/context`. Override with `SLASH_COMMAND_TOOL_CHAR_BUDGET` env var.
