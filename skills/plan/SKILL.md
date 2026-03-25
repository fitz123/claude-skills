---
name: plan
description: Create structured implementation plan in docs/plans/. Use when user says 'plan', 'write a plan', 'make a plan', or after brainstorming to formalize design into actionable tasks. NOT for ralphex-specific plans — use ralphex-plan skill for those.
argument-hint: describe the feature or task to plan
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion, Agent, EnterPlanMode, ExitPlanMode
---

# Implementation Plan

Create an implementation plan in `docs/plans/yyyymmdd-<task-name>.md`.

## Step 0: Parse Intent and Gather Context

Before asking questions, understand what the user is working on:

1. **Parse arguments** to identify intent:
   - "add feature Z" / "implement W" → feature development
   - "fix bug" / "debug issue" → bug fix plan
   - "refactor X" / "improve Y" → refactoring plan
   - "migrate to Z" / "upgrade W" → migration plan
   - generic request → explore current work

2. **Launch Explore agent** to gather relevant context based on intent:
   - Locate related existing code and patterns
   - Check project structure and similar implementations
   - Identify affected components and dependencies
   - Check recent changes in problem areas

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

Check `docs/plans/` for existing files, then create `docs/plans/yyyymmdd-<task-name>.md` (use current date).

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

After writing the plan, launch the `plan-review` agent to validate quality:

The plan-review agent (read-only, opus model) checks:
- Problem definition and solution correctness
- Over-engineering and scope creep
- Testing requirements per task
- Task granularity and convention adherence

If review returns **NEEDS REVISION**:
1. Address all critical and important issues
2. Re-run the plan-review agent
3. Repeat until APPROVE or user overrides

If review returns **APPROVE**, proceed to Step 4.

## Step 4: Present to User

After auto-review passes, use AskUserQuestion:

```json
{
  "questions": [{
    "question": "Plan reviewed and approved by AI reviewer. What's next?",
    "header": "Next step",
    "options": [
      {"label": "Review in plannotator (Recommended)", "description": "Open plan in plannotator for visual review and annotation"},
      {"label": "Start implementation", "description": "Commit plan and begin with task 1"},
      {"label": "Done", "description": "Commit plan, implement later"}
    ],
    "multiSelect": false
  }]
}
```

- **Review in plannotator**: call ExitPlanMode to trigger plannotator's visual UI. User can annotate, approve, or request changes. If changes requested, revise the plan and call ExitPlanMode again
- **Start implementation**: commit plan, begin with task 1
- **Done**: commit plan with message like "docs: add <topic> implementation plan"

## Key Principles

- **One question at a time** - do not overwhelm user with multiple questions
- **Multiple choice preferred** - easier to answer than open-ended when possible
- **YAGNI ruthlessly** - keep scope minimal
- **Lead with recommendation** - have an opinion, explain why, but let user decide
- **Explore alternatives** - propose 2-3 approaches before settling (unless obvious)
