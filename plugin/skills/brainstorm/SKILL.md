---
name: brainstorm
description: Turn ideas into designs through collaborative dialogue before implementation. Use when user says 'brainstorm', 'let's brainstorm', 'deep analysis', 'think through', 'help me design', 'explore options for', or when user asks for thorough analysis of changes, features, or architectural decisions.
argument-hint: "[topic]"
allowed-tools:
  - Read(*)
  - Glob(*)
  - Grep(*)
  - Bash(git:*)
  - AskUserQuestion
  - Skill
  - Agent(*)
  - EnterPlanMode
  - ExitPlanMode
---

# Brainstorm

Turn ideas into designs through collaborative dialogue, then enter plan mode for implementation.

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

### Phase 4: Plan Mode + Plannotator

After design is validated, always enter plan mode for structured planning:

1. Call `EnterPlanMode` — the system provides a plan file path in the plan mode instructions
2. Write a structured implementation plan to the plan mode file. Include all brainstorm context: selected approach, design decisions, files involved, constraints, testing preference. Structure as tasks with `- [ ]` checkboxes
3. Call `ExitPlanMode` — this triggers plannotator's visual UI where the user can annotate, approve, or request changes

**Revision loop:** When the user submits annotations via plannotator, their feedback appears as a user message. The system automatically re-enters plan mode. Revise the plan in the plan mode file and call `ExitPlanMode` again to re-trigger plannotator. Repeat until approved.

### Phase 5: Execute

After plan is approved, use AskUserQuestion tool:

```json
{
  "questions": [{
    "question": "Plan approved. How to execute?",
    "header": "Execution",
    "options": [
      {"label": "Start now (Recommended)", "description": "Begin implementing task by task"},
      {"label": "Ralphex plan", "description": "Create a ralphex plan for autonomous execution (requires ralphex plugin)"}
    ],
    "multiSelect": false
  }]
}
```

#### Start now

Begin implementing starting with task 1 from the approved plan.

#### Ralphex plan

Invoke the ralphex-plan skill (from the ralphex companion plugin), passing full brainstorm context and the approved plan:

```
Skill(skill="ralphex:ralphex-plan", args="<summary of: selected approach, design decisions, files involved, constraints>")
```

The ralphex-plan skill creates a plan file in `docs/plans/` formatted for autonomous execution by the ralphex CLI.

**Requires the `umputun/ralphex` plugin.** If the Skill call fails (plugin not installed), inform the user:
> Ralphex plugin not installed. Install with: `/plugin marketplace add umputun/ralphex` then `/plugin install ralphex --scope user`

## Example Session

```
User: /brainstorm add webhook support to our API

Phase 1: [reads codebase, finds existing API structure]
  Q: "What events should trigger webhooks?" (multiple choice)
  Q: "Should webhooks be async or sync?" (multiple choice)
  Q: "Any delivery guarantees needed?" (multiple choice)

Phase 2: [proposes approaches]
  Option A: Simple HTTP POST per event (recommended)
  Option B: Message queue with worker
  → User picks Option A

Phase 3: [presents design in sections]
  Section 1: Event registration model → user approves
  Section 2: Delivery mechanism → user approves
  Section 3: Retry strategy → user adjusts

Phase 4: [always enters plan mode]
  → EnterPlanMode → writes plan with tasks → ExitPlanMode
  → plannotator opens in browser
  → user annotates: "add rate limiting to Task 3"
  → revises plan, ExitPlanMode again
  → user approves

Phase 5: [AskUserQuestion: Start now / Ralphex plan]
  → User picks "Start now" → begins task 1
  or
  → User picks "Ralphex plan" → creates docs/plans/ file for ralphex CLI
```

## Key Principles

- **One question at a time** - do not overwhelm with multiple questions
- **Multiple choice preferred** - easier to answer than open-ended when possible
- **YAGNI ruthlessly** - remove unnecessary features from all designs, keep scope minimal
- **Explore alternatives** - always propose 2-3 approaches before settling
- **Incremental validation** - present design in sections, validate each
- **Be flexible** - go back and clarify when something doesn't make sense
- **Lead with recommendation** - have an opinion, explain why, but let user decide
- **Duplication vs abstraction** - when code repeats, ask user: prefer duplication (simpler, no coupling) or abstraction (DRY but adds complexity)? explain trade-offs before deciding
