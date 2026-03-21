---
name: brainstorm
description: Transforms ideas into concrete designs with interactive proposal selection. Use when starting features, exploring solutions, planning projects, or when user says 'brainstorm', 'let's think about', 'help me design', 'I want to build', 'what if we'.
---

# Brainstorming

Transform ideas into actionable designs through structured discovery with interactive selection.

## Activation

```
/brainstorm [topic] [--depth quick|standard|deep]
```

**Depth levels:**
- `quick`: 2-3 questions, 1 approach, minimal docs
- `standard` (default): 5-7 questions, 2-3 approaches, full design doc
- `deep`: 10+ questions, exhaustive analysis, detailed specifications

## Core Behavior

**CRITICAL RULES:**
1. **USE AskUserQuestion TOOL** for ALL choices - never text-based A/B/C/D
2. Ask ONE question per message - wait for response before continuing
3. Present recommended option FIRST with "(Recommended)" in label
4. Apply YAGNI ruthlessly - no speculative features
5. Validate each design section before proceeding

## Using AskUserQuestion

For EVERY decision point, use the AskUserQuestion tool.

**Choose multiSelect based on the question type:**

| Question Type | multiSelect | Example |
|---------------|-------------|---------|
| Pick ONE approach | `false` | "Which architecture?" |
| Pick ONE priority | `false` | "What takes precedence?" |
| Select MULTIPLE features | `true` | "What should it support?" |
| Select MULTIPLE constraints | `true` | "What constraints exist?" |
| Yes/No decision | `false` | "Does this work?" |

**Single selection** (mutually exclusive - user picks ONE):
```json
{
  "questions": [{
    "question": "Which architecture approach fits best?",
    "header": "Approach",
    "multiSelect": false,
    "options": [
      {"label": "Monolith (Recommended)", "description": "Single deployable unit"},
      {"label": "Microservices", "description": "Distributed services"},
      {"label": "Serverless", "description": "Function-based"}
    ]
  }]
}
```

**Multiple selection** (can pick several):
```json
{
  "questions": [{
    "question": "What constraints exist for this project?",
    "header": "Constraints",
    "multiSelect": true,
    "options": [
      {"label": "Limited budget", "description": "Cost is a major factor"},
      {"label": "Tight timeline", "description": "Need quick delivery"},
      {"label": "Legacy compatibility", "description": "Must work with existing systems"},
      {"label": "Compliance requirements", "description": "Security/regulatory needs"}
    ]
  }]
}
```

**Multiple questions at once** (when asking related but independent things):
```json
{
  "questions": [
    {
      "question": "Who will use this feature?",
      "header": "Users",
      "multiSelect": false,
      "options": [
        {"label": "Internal team", "description": "Staff only"},
        {"label": "End users", "description": "Customers"},
        {"label": "Developers", "description": "API consumers"}
      ]
    },
    {
      "question": "What capabilities are needed?",
      "header": "Features",
      "multiSelect": true,
      "options": [
        {"label": "CRUD operations", "description": "Create, read, update, delete"},
        {"label": "Search/filter", "description": "Find and filter data"},
        {"label": "Export", "description": "Download data"},
        {"label": "Notifications", "description": "Alerts and updates"}
      ]
    }
  ]
}
```

Users can always select "Other" to provide custom input.

## Using Sequential Thinking

Use the `mcp__sequential-thinking__sequentialthinking` tool for complex analysis that requires step-by-step reasoning.

**When to use:**
- Comparing multiple approaches with trade-offs
- Analyzing complex requirements with dependencies
- Breaking down ambiguous problems
- Evaluating architectural decisions
- When you need to revise or backtrack on earlier thinking

**When NOT to use:**
- Simple yes/no decisions
- Straightforward feature requests
- Quick depth brainstorming

**Example usage in EXPLORE phase:**
```json
{
  "thought": "Analyzing the three architectural approaches for the user's requirements...",
  "thoughtNumber": 1,
  "totalThoughts": 4,
  "nextThoughtNeeded": true
}
```

**Key parameters:**
- `thought`: Current reasoning step
- `thoughtNumber` / `totalThoughts`: Track progress (can adjust totalThoughts as needed)
- `nextThoughtNeeded`: true to continue, false when done
- `isRevision`: true if reconsidering a previous thought
- `revisesThought`: which thought number is being revised
- `needsMoreThoughts`: set true if reaching end but need more analysis

**Workflow:**
1. Start with estimated total thoughts (usually 3-5)
2. Reason through each aspect step by step
3. Revise earlier thoughts if new insights emerge
4. Adjust totalThoughts up/down as needed
5. Set `nextThoughtNeeded: false` when analysis complete
6. Present conclusion to user via AskUserQuestion

## Phase 1: UNDERSTAND (5-15%)

Gather context before proposing anything.

**First:** Read project context silently (CLAUDE.md, README, existing structure).

**Then use AskUserQuestion for each:**

1. Problem identification
2. Target users (internal team / end users / developers / other)
3. Success criteria
4. Constraints (budget, timeline, tech stack)
5. Non-goals (what should this NOT do)

**Example AskUserQuestion:**

```json
{
  "questions": [{
    "question": "Who will use this feature?",
    "header": "Users",
    "multiSelect": false,
    "options": [
      {"label": "Internal team (Recommended)", "description": "Staff and internal processes"},
      {"label": "End users", "description": "External customers"},
      {"label": "Other developers", "description": "API/library consumers"}
    ]
  }]
}
```

## Phase 2: EXPLORE (20-30%)

**For complex problems:** Use Sequential Thinking first to analyze approaches, then present via AskUserQuestion.

Present 2-3 approaches using AskUserQuestion. Lead with recommendation.

**Format each option:**
- Label: Short name + "(Recommended)" for best option
- Description: What it is, key pros/cons, complexity level

**Example:**

```json
{
  "questions": [{
    "question": "Based on your requirements, which approach fits best?",
    "header": "Approach",
    "multiSelect": false,
    "options": [
      {
        "label": "Event-driven (Recommended)",
        "description": "Pub/sub pattern. Pros: loose coupling, scalable. Cons: eventual consistency. Best for your async needs."
      },
      {
        "label": "Direct API calls",
        "description": "Synchronous REST. Pros: simple, immediate. Cons: tight coupling. Better for simple cases."
      },
      {
        "label": "Hybrid approach",
        "description": "API for reads, events for writes. Pros: balanced. Cons: more complex. Good for mixed requirements."
      }
    ]
  }]
}
```

After selection, briefly explain WHY the chosen approach works for their case.

## Phase 3: DESIGN (40-50%)

Break design into 200-300 word sections. Validate EACH section with AskUserQuestion.

**For complex architecture:** Use Sequential Thinking to work through component interactions, data flow, and edge cases before presenting each section.

**Cover these areas:**
1. Architecture overview
2. Key components and responsibilities
3. Data flow
4. Error handling approach
5. Testing strategy

**Use visuals when helpful:**
```
┌─────────────┐     ┌─────────────┐
│   Client    │────▶│     API     │
└─────────────┘     └──────┬──────┘
                          │
                   ┌──────▼──────┐
                   │   Service   │
                   └─────────────┘
```

**After each section, use AskUserQuestion:**

```json
{
  "questions": [{
    "question": "Does this architecture work for your needs?",
    "header": "Review",
    "multiSelect": false,
    "options": [
      {"label": "Yes, continue", "description": "Proceed to next section"},
      {"label": "Questions", "description": "I need clarification on something"},
      {"label": "Adjust", "description": "I want to change something"}
    ]
  }]
}
```

## Phase 4: DOCUMENT (10-20%)

Save validated design to `docs/plans/YYYY-MM-DD-<topic>-design.md`

**Template:**
```markdown
# [Topic] Design

**Date:** YYYY-MM-DD
**Status:** Draft | Approved | Implemented

## Problem Statement
[From UNDERSTAND phase]

## Decision
**Chosen approach:** [Option name]
**Rationale:** [Why this over alternatives]

## Architecture
[Diagram and explanation]

## Components
| Component | Responsibility | Dependencies |
|-----------|---------------|--------------|

## Implementation Steps
1. [ ] Step 1
2. [ ] Step 2

## Open Questions
- [ ] Question 1
```

**Final AskUserQuestion:**

```json
{
  "questions": [{
    "question": "Design saved. What's next?",
    "header": "Next step",
    "multiSelect": false,
    "options": [
      {"label": "Start implementation (Recommended)", "description": "Begin coding based on this design"},
      {"label": "Commit to git", "description": "Save design doc to version control"},
      {"label": "Review first", "description": "Go back and revise something"},
      {"label": "Done for now", "description": "Stop here, implement later"}
    ]
  }]
}
```

## Rules

### DO
- Use AskUserQuestion for ALL choices
- Use `multiSelect: true` when user can pick multiple (features, constraints, requirements)
- Use `multiSelect: false` when choices are mutually exclusive (approaches, priorities)
- Batch related independent questions in one AskUserQuestion call (up to 4 questions)
- Use Sequential Thinking for complex trade-off analysis before presenting options
- Explore codebase BEFORE proposing solutions
- Reference existing patterns in the project
- Put recommended option FIRST

### DON'T
- Use text-based A/B/C/D choices (use AskUserQuestion instead)
- Assume requirements without verification
- Present more than 4 options per question (tool limit)
- Make decisions FOR the user
- Use multiSelect for mutually exclusive choices
- Use single select when user might need multiple options

## Red Flags

| Signal | Response |
|--------|----------|
| User says "just do it" | Use AskUserQuestion with minimal clarifying options |
| Contradictory requirements | Use AskUserQuestion to pick priority |
| Massive scope | Use AskUserQuestion to select phasing approach |
| User seems uncertain | Present 3 concrete paths via AskUserQuestion |

## Quick Reference

| Phase | Time | Goal | Key Tools |
|-------|------|------|-----------|
| UNDERSTAND | 5-15% | Clarify scope | AskUserQuestion |
| EXPLORE | 20-30% | Compare options | Sequential Thinking → AskUserQuestion |
| DESIGN | 40-50% | Detail solution | Sequential Thinking + AskUserQuestion + visuals |
| DOCUMENT | 10-20% | Record decisions | Write + AskUserQuestion |
