---
name: ralphex-plan
description: Creates ralphex plan files for automated code changes. Use when user says 'write a plan', 'ralphex plan', 'create plan for ralphex', or needs to prepare a plan file for ralphex execution.
argument-hint: "[topic or description]"
allowed-tools:
  - Read(*)
  - Write(*)
  - Edit(*)
  - Glob(*)
  - Grep(*)
  - Bash(git:*)
  - Bash(ssh:*)
  - Agent(*)
---

# Ralphex Plan Writer

Creates plan files for [umputun/ralphex](https://github.com/umputun/ralphex) — an automated multi-agent code review and implementation tool. Ralphex reads the plan, executes tasks sequentially in fresh Claude Code sessions, runs validation after each task, then reviews changes through a multi-agent pipeline.

## Plan File Format

```markdown
# Descriptive Title — Round N

## Goal

1-2 sentences: what we're achieving and why.

## Validation Commands

```bash
<commands that verify correctness — tests, type checks, linters>
```

## Reference: <topic>

Factual data about current state — real CLI output, type definitions,
code snippets showing the bug, API docs. NOT proposed solutions.

## Tasks

### Task N: Short description (ticket-id, priority)

Problem statement: what's broken, evidence, user impact.
What we want: desired outcome (not implementation steps).

- [ ] Verifiable outcome 1
- [ ] Verifiable outcome 2
- [ ] Add tests
- [ ] Verify existing tests pass
```

## Writing Principles

### 1. Describe Problems, Not Solutions

Ralphex has full access to the codebase. It will research, find the right approach, implement, test, and iterate through review. The plan should explain:

- **What's broken** — observable symptoms, error messages, user impact
- **Why it matters** — business/UX consequence
- **What we want** — desired behavior after the fix
- **Evidence** — real logs, screenshots, error codes that prove the problem

Do NOT include:
- Implementation code (no "create function X that does Y")
- Architecture decisions (no "use a transformer chain before auto-retry")
- Step-by-step implementation instructions
- Migration rules or code snippets of the proposed solution

### 2. Reference Sections Prevent Wrong Guesses

Reference sections provide **factual data about current state** that ralphex would otherwise have to guess. They are the most impactful part of a plan. Include:

- **Real CLI/API output** — actual JSON event shapes, not hypothetical ones
- **Current code showing the bug** — exact snippets with file and line numbers
- **Type definitions** — interfaces ralphex will need to extend or use
- **Library API docs** — how the framework actually works (not how you think it works)
- **Config format** — current YAML/JSON structure that needs new fields

Reference sections describe **what IS**, never **what should be**. They are read-only context, not instructions.

### 3. Checkboxes Are Verifiable Outcomes

Each checkbox should describe a **testable result**, not an implementation step:

Good:
- `- [ ] 429 rate limit errors are logged at WARN level with method and retry_after`
- `- [ ] Final message text is delivered even when editMessageText fails`
- `- [ ] Add tests reproducing the truncated message scenario`

Bad:
- `- [ ] Create src/logger.ts` (implementation detail)
- `- [ ] Add try/catch around editMessageText` (how, not what)
- `- [ ] Use transformer API to intercept errors` (prescriptive)

### 4. Task Granularity

- Each task = one logical unit of work (a bug fix, a feature, a module)
- Tasks execute in separate Claude Code sessions — no shared state between tasks
- Order tasks so later ones can build on earlier ones
- Always end with "Add tests" and "Verify existing tests pass" checkboxes
- Include ticket IDs and priority (P0/P1/P2) in the task header

### 5. Goal Section

Keep it brief — 1-2 sentences covering what and why. This is the high-level context that frames all tasks.

### 6. Validation Commands

Commands that run after EVERY task. Must be fast and comprehensive enough to catch regressions. Typical patterns:
- TypeScript: `npx tsc --noEmit` + `npm test`
- Go: `go test ./...` + `golangci-lint run`
- Python: `pytest` + `mypy .`

## Workflow

1. **Gather context** — read relevant source files, logs, error reports, beads tickets
2. **Identify problems** — list observable issues with evidence
3. **Research references** — collect factual data (real output, types, API docs, current code)
4. **Write the plan** — problems + references + desired outcomes, no implementation
5. **Review** — check that no implementation details leaked in, references are factual
6. **Save** — write to the project's plans directory

## Anti-Patterns From Real Experience

These mistakes were observed in actual ralphex runs and caused problems:

| Anti-Pattern | What Happened | Better Approach |
|---|---|---|
| Prescribing implementation code | Ralphex followed it blindly even when a better approach existed | Describe the problem, let ralphex research |
| Wrong API assumptions | Plan said "autoRetry has an onRetry callback" — it doesn't | Include real API docs or say "research how X works" |
| Missing reference data | Plan didn't include real event shapes, ralphex guessed wrong type format | Always include real CLI/API output samples |
| Too many tasks in one plan | Review pipeline runs N times longer | 2-4 tasks per plan is optimal |
| Vague checkboxes | "Implement feature" — not verifiable | Specific outcome: "X is logged at Y level with Z data" |
