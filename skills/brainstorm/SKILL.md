---
name: brainstorm
description: Turn ideas into designs through collaborative dialogue before implementation. Use when user says 'brainstorm', 'let's brainstorm', 'deep analysis', 'think through', 'help me design', 'explore options for', or when user asks for thorough analysis of changes, features, or architectural decisions.
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion, Skill
---

# Brainstorm

Turn ideas into designs through collaborative dialogue before implementation.

## Process

### Phase 1: Understand the Idea

Check project context first, then ask questions one at a time:

1. **Gather context** - check files, docs, recent commits relevant to the idea
2. **Ask questions one at a time** - prefer multiple choice when possible
3. **Focus on**: purpose, constraints, success criteria, integration points

Do not overwhelm with multiple questions. One question per message. If a topic needs more exploration, break it into multiple questions.

### Phase 2: Explore Approaches

Once the problem is understood:

1. **Propose 2-3 different approaches** with trade-offs
2. **Lead with recommended option** and explain reasoning
3. **Present conversationally** - not a formal document yet

Example format:
```
I see three approaches:

**Option A: [name]** (recommended)
- how it works: ...
- pros: ...
- cons: ...

**Option B: [name]**
- how it works: ...
- pros: ...
- cons: ...

Which direction appeals to you?
```

### Phase 3: Present Design

After approach is selected:

1. **Break design into sections** of 200-300 words each
2. **Ask after each section** whether it looks right
3. **Cover**: architecture, components, data flow, error handling, testing
4. **Be ready to backtrack** if something doesn't make sense

Do not present entire design at once. Incremental validation catches misunderstandings early.

### Phase 4: Next Steps

After design is validated, use AskUserQuestion tool:

```json
{
  "questions": [{
    "question": "Design looks complete. What's next?",
    "header": "Next step",
    "options": [
      {"label": "Write plan (Recommended)", "description": "Create implementation plan via /plan with full brainstorm context"},
      {"label": "Start now", "description": "Begin implementing directly"}
    ],
    "multiSelect": false
  }]
}
```

- **Write plan**: invoke `/plan` skill. Pass brainstorm context (discovered files, selected approach, design decisions, constraints) as arguments so the plan skill has full context without re-asking questions
- **Start now**: proceed directly if design is simple enough

## Key Principles

- **One question at a time** - do not overwhelm with multiple questions
- **Multiple choice preferred** - easier to answer than open-ended when possible
- **YAGNI ruthlessly** - remove unnecessary features from all designs, keep scope minimal
- **Explore alternatives** - always propose 2-3 approaches before settling
- **Incremental validation** - present design in sections, validate each
- **Be flexible** - go back and clarify when something doesn't make sense
- **Lead with recommendation** - have an opinion, explain why, but let user decide
- **Duplication vs abstraction** - when code repeats, ask user: prefer duplication (simpler, no coupling) or abstraction (DRY but adds complexity)? explain trade-offs before deciding
