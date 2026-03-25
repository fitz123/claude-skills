---
name: plan
description: Create structured implementation plan in docs/plans/. Use when user says 'plan', 'write a plan', 'make a plan', or after brainstorming to formalize design into actionable tasks. NOT for ralphex-specific plans — use ralphex-plan skill for those.
argument-hint: "[description] or context summary from brainstorm"
allowed-tools:
  - Read(*)
  - Write(*)
  - Edit(*)
  - Glob(*)
  - Grep(*)
  - Bash(git:*)
  - Bash(mkdir:*)
  - AskUserQuestion
  - Agent(*)
  - EnterPlanMode
  - ExitPlanMode
---

# Implementation Plan

Create an implementation plan in `docs/plans/yyyymmdd-<task-name>.md`.

## Step 0: Parse Intent and Gather Context

Before asking questions, understand what the user is working on:

1. **Parse arguments** to identify intent and detect brainstorm context:
   - If arguments contain a context summary from brainstorm (approach, decisions, files, constraints), extract these and skip Steps 1 and 1.5
   - "add feature Z" / "implement W" → feature development
   - "fix bug" / "debug issue" → bug fix plan
   - "refactor X" / "improve Y" → refactoring plan
   - "migrate to Z" / "upgrade W" → migration plan
   - generic request → explore current work

2. **Launch Explore agent** (subagent_type: "Explore") to gather relevant context based on intent. Provide the agent with a focused search prompt:

   ```
   Agent(
     subagent_type="Explore",
     description="plan-context-exploration",
     prompt="Explore the codebase for context related to: <TASK_DESCRIPTION>.
     Find: relevant source files and patterns, project structure,
     affected components and dependencies, recent changes in problem areas.
     Working directory: <CWD>"
   )
   ```

3. **Synthesize findings** into context summary

## Step 1: Present Context and Ask Focused Questions

Show the discovered context, then ask questions **one at a time** using AskUserQuestion:

1. **Plan purpose** - "what is the main goal?" (multiple choice with suggested answer)
2. **Scope** - "which components/files are involved?" (multiple choice with discovered files)
3. **Constraints** - "any specific requirements or limitations?"
4. **Testing approach** - "TDD or regular?"
5. **Plan title** - "short descriptive title?" (suggest based on intent)

**Skip questions** where the answer is obvious from context or was already provided via brainstorm.

## Step 1.5: Explore Approaches

Once the problem is understood, propose implementation approaches:

1. **Propose 2-3 different approaches** with trade-offs
2. **Lead with recommended option** and explain reasoning
3. Use AskUserQuestion to let user select preferred approach

**Skip this step** if:
- The implementation approach is obvious
- User explicitly specified how they want it done
- Context was already provided via brainstorm with a selected approach

## Step 2: Create Plan File

Run `mkdir -p docs/plans` to ensure the directory exists. Check for existing files, then create `docs/plans/yyyymmdd-<task-name>.md` (use current date).

Store the full path as `PLAN_FILE_PATH` for use in later steps.

### Plan Structure

```markdown
# [Plan Title]

## Overview
- Clear description of the feature/change
- Problem it solves and key benefits
- How it integrates with existing system

## Context (from discovery)
- Files/components involved
- Related patterns found
- Dependencies identified

## Development Approach
- **Testing approach**: [TDD / Regular]
- Complete each task fully before moving to the next
- Every task MUST include new/updated tests
- All tests must pass before starting next task

## Implementation Steps

### Task 1: [specific name]

**Files:**
- Create: `exact/path/to/new_file`
- Modify: `exact/path/to/existing`

- [ ] [specific action with file reference]
- [ ] [specific action with file reference]
- [ ] write tests for new/changed functionality
- [ ] run tests - must pass before next task

### Task N-1: Verify acceptance criteria
- [ ] verify all requirements from Overview are implemented
- [ ] run full test suite
- [ ] run linter

### Task N: Update documentation
- [ ] update README.md if needed
- [ ] update CLAUDE.md if new patterns discovered

## Technical Details
- Data structures and changes
- Processing flow
```

## Step 3: Auto-Review

After writing the plan, launch the `plan-review` agent to validate quality. Pass the exact plan file path so it reviews the right file:

```
Agent(
  subagent_type="plan-review",
  description="plan-auto-review",
  prompt="Review the implementation plan at: <PLAN_FILE_PATH>"
)
```

The plan-review agent (read-only, opus model) checks:
- Problem definition and solution correctness
- Over-engineering and scope creep
- Testing requirements per task
- Task granularity and convention adherence

**Review loop (max 3 rounds):**

```
REVIEW_ROUND = 0

loop:
  REVIEW_ROUND += 1
  if REVIEW_ROUND > 3:
    present remaining issues to user and proceed to Step 4
    break

  launch plan-review agent with PLAN_FILE_PATH

  if verdict == APPROVE:
    proceed to Step 4
    break

  if verdict == NEEDS REVISION:
    address all critical and important issues in the plan file
    continue loop
```

## Step 4: Present to User via Plannotator

After auto-review passes (or max rounds reached):

1. Call `EnterPlanMode` — this activates plan mode. The system will provide a plan file path in the plan mode instructions (visible in the system message). This is a separate file from `docs/plans/`
2. Write the plan content to the plan mode file path provided by the system
3. Call `ExitPlanMode` — this triggers plannotator's visual UI in the browser where the user can annotate, approve, or request changes

**How plannotator feedback works:** When the user submits annotations in plannotator, their feedback appears as a user message in the conversation. Read the feedback, revise the plan (update both the plan mode file and the `docs/plans/` file), then call `ExitPlanMode` again. Repeat until the user approves.

After approval, use AskUserQuestion:

```json
{
  "questions": [{
    "question": "Plan approved. What's next?",
    "header": "Next step",
    "options": [
      {"label": "Start implementation (Recommended)", "description": "Commit plan and begin with task 1"},
      {"label": "Done", "description": "Commit plan, implement later"}
    ],
    "multiSelect": false
  }]
}
```

- **Start implementation**: commit plan, begin with task 1
- **Done**: commit plan with message like "docs: add <topic> implementation plan"

## Example Session

```
User: /plan (invoked from brainstorm with context)
  → Step 0: detects brainstorm context, skips Steps 1 and 1.5
  → Step 2: writes docs/plans/20260325-webhook-support.md
  → Step 3: launches plan-review agent
    Round 1: NEEDS REVISION (Task 2 bundles auth + delivery)
    → fixes plan, splits Task 2
    Round 2: APPROVE
  → Step 4: EnterPlanMode → writes plan to plan mode file → ExitPlanMode
    → plannotator opens in browser
    → user adds annotation: "add rate limiting to Task 3"
    → revises plan, calls ExitPlanMode again
    → user approves
  → AskUserQuestion: Start / Done
    → user picks "Start implementation"
    → commits plan, begins Task 1
```

## Key Principles

- **One question at a time** - do not overwhelm user with multiple questions
- **Multiple choice preferred** - easier to answer than open-ended when possible
- **YAGNI ruthlessly** - keep scope minimal
- **Lead with recommendation** - have an opinion, explain why, but let user decide
- **Explore alternatives** - propose 2-3 approaches before settling (unless obvious)
