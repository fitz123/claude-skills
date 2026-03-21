---
name: ralphex
description: Runs parallel multi-agent code review (quality, implementation, testing, simplification, documentation), verifies findings, fixes confirmed issues, then iterates automatically (codex cross-review up to 3 rounds, second-pass up to 3 rounds) until clean. Use when reviewing branch changes, after implementing features, or when user says 'review' or 'ralphex'.
argument-hint: "[base-branch]"
allowed-tools:
  - Bash(git:*)
  - Bash(make:*)
  - Bash(npm:*)
  - Bash(yarn:*)
  - Bash(pnpm:*)
  - Bash(cargo:*)
  - Bash(go:*)
  - Bash(pytest:*)
  - Bash(python:*)
  - Bash(codex:*)
  - Bash(which:*)
  - Read(*)
  - Write(*)
  - Edit(*)
  - Glob(*)
  - Grep(*)
  - Task(*)
---

# Ralphex — Multi-Agent Code Review

Adapted from the review pipeline of [umputun/ralphex](https://github.com/umputun/ralphex). Implements Phases 2-4 (multi-agent review, external review, second pass) as a prompt-only workflow. Plan execution, finalize step, web dashboard, and notifications are not included.

5 specialized agents review changes in parallel, findings are verified and fixed. The pipeline runs automatically end-to-end after Step 1 scope selection — no user intervention needed during iteration loops. Commits are made automatically; a full summary is presented at the end.

**Pipeline overview:** Step 1 (scope) → Step 2 (5 agents) → Step 3 (verify) → Step 4 (fix + auto-commit) → Step 5 (codex loop, up to 3 rounds) → Step 6 (second-pass loop, up to 3 rounds) → done. Early exit at Step 3 if no issues found.

**Invoke from the target repo's directory.** All git commands run against CWD — do not use `git -C`.

```
/ralphex            # diff against main
/ralphex develop    # diff against develop
```

## Step 1: Gather Context

Determine the base branch (argument or default `main`). Verify it exists: `git rev-parse --verify <base>`. If the branch does not exist, list available branches with `git branch -a`, suggest the closest match, and ask the user which branch to use.

Check working tree state:

- `git log <base>..HEAD --oneline` — diverged commits
- `git diff <base>...HEAD --stat` — changes in diverged commits
- `git diff --stat` — unstaged changes
- `git diff --cached --stat` — staged changes
- `git status --short` — working tree status (staged, unstaged, untracked)

Determine review scope:

- If diverged commits exist, primary scope is `git diff <base>...HEAD`. If working tree is also dirty, review only committed changes (uncommitted changes are out of scope). Mention the dirty state in the report so the user is aware.
- If no diverged commits but unstaged/staged/untracked changes exist, set `DIFF_MODE=uncommitted`.
- If nothing to review, say so and stop.

## Step 2: Launch 5 Agents in Parallel

Send a SINGLE message with 5 Task tool calls (`subagent_type: "general-purpose"`). Do NOT use `run_in_background` — foreground agents run in parallel and block until all complete. Individual agent retries (line below) are permitted as separate follow-up messages.

**Review agents are READ-ONLY.** They must not edit, write, or commit. Only the main orchestrator edits files.

Each agent gets the preamble + its specific prompt below, with `{base}` replaced by the actual base branch.
If `DIFF_MODE=uncommitted`, replace the first preamble line (the `git diff {base}...HEAD` line) with: "Get changes: run `git diff`, `git diff --cached`, and `git diff --stat` to see all uncommitted and staged changes."

Preamble (prepend to every agent prompt):

```
Get changes: run git diff {base}...HEAD and git diff --stat {base}...HEAD.
Also check git status --short for untracked files relevant to the diff and read those.
Read the actual source files for full context. Do NOT edit or commit anything.
Report pre-existing issues too — do not dismiss findings just because code existed before this branch.
Output plain text only — no markdown bold, code blocks, or headers. Use - lists.
If no issues found, respond with exactly: No issues found.
```

**Quality** — bugs, security, error handling, races, leaks, information exposure:

```
Check for:
1. Logic errors - off-by-one, incorrect conditionals, wrong operators
2. Edge cases - empty inputs, nil values, boundary conditions, concurrent access
3. Error handling - all errors checked, proper wrapping, no silent failures
4. Resource management - proper cleanup, no leaks (file handles, connections, goroutines)
5. Concurrency - race conditions, deadlocks, unsafe shared state
6. Security - input validation, auth, injection, secret exposure, unintended information leakage
7. Data integrity - validation, sanitization, consistent state management
Prioritize straightforward implementations. Question unnecessary abstractions.
Report: file:line, severity (critical/major/minor), issue, impact, fix suggestion.
```

**Implementation** — requirement coverage, correctness, wiring, completeness:

```
Check for:
1. Requirement coverage - all aspects of the goal addressed? Unhandled scenarios?
2. Correctness of approach - solving the right problem? Potential failure conditions?
3. Wiring and integration - components registered, routes added, handlers connected, configs updated?
4. Completeness - missing imports, unimplemented interfaces, incomplete migrations?
5. Logic flow - data flows correctly input to output, transformations correct, state managed properly?
6. Edge cases - empty inputs, null values, concurrent operations, error scenarios at boundaries
Ignore style — focus on correctness and approach validity.
Report: file:line, severity (critical/major/minor), issue, impact, fix suggestion.
```

**Testing** — missing tests, fake tests, independence, edge cases:

```
Check for:
1. Missing tests - new code paths without tests, untested error paths, no integration tests at system boundaries
2. Fake tests - always pass, check hardcoded values, verify mocks not code, conditional assertions, commented-out failing tests
3. Test quality - verify behavior not implementation, descriptive names, proper setup/teardown, both success and failure scenarios
4. Test independence - no shared mutable state, no order dependencies, proper isolation
5. Edge case coverage - empty, nil, zero, max, concurrent, timeout
6. Coverage gaps - functions or branches without test coverage
Report: file:line, severity (critical/major/minor), issue, impact, fix suggestion.
```

**Simplification** — over-engineering, unnecessary abstraction:

```
Check for:
1. Excessive abstraction - wrappers adding nothing, factories for single impl, interface on producer side, handler->service->repository pass-through layers
2. Premature generalization - generic solutions for specific problems (event bus for one event type), config objects for 2 options
3. Unnecessary indirection - pass-through wrappers, excessive chaining, DTO/mapper overkill, wrapper interfaces around primitive types
4. Future-proofing - unused extension points, permanent feature flags, versioned internal APIs with single version
5. Unnecessary fallbacks - unreachable fallback paths, disabled legacy code, dual implementations, error-suppressing fallbacks that mask problems
6. Premature optimization - caching rarely-accessed data, custom structures when standard collections work, connection pooling for minimal operations
Report: file:line, severity (critical/major/minor), pattern, problem, simpler alternative, effort (trivial/small/medium/large).
```

**Documentation** — README gaps, CLAUDE.md gaps, plan updates:

```
Check README.md - must document: new features, CLI flags, API endpoints, config options, breaking changes, new deps.
Skip: internal refactoring, bug fixes restoring documented behavior, test additions.
Check CLAUDE.md - must document: new patterns, conventions, build commands, structure changes.
Skip: standard code following existing patterns, simple fixes.
Check plan files (docs/plans/, PLAN.md, TODO.md) if they exist - mark completed items, update status.
Report: what is missing, where it goes, suggested content. Report problems only — no positive observations.
```

**If any agent fails or returns empty/garbage:** retry that single agent once in a separate message. If still failing, proceed without it and note the gap in the report.

## Step 3: Verify Findings

Collect all agent findings. If no findings were reported (all responding agents said "No issues found"), report that the review is clean and stop — skip Steps 4-6. If an agent was skipped due to failure, note the gap but still stop if there are zero findings.

For EACH issue (documentation findings may use file+section instead of file:line):

1. Read actual code at file:line
2. Check 20-30 lines of surrounding context
3. Verify issue is real, merge duplicates from multiple agents
4. Check for existing mitigations

Classify:

- **CONFIRMED** — real issue, fix it
- **FALSE POSITIVE** — discard with brief reason

If ALL findings are false positives, report "No actionable issues found" with the false positive list and stop.

## Step 4: Report and Fix

Present summary to the user with confirmed issues, false positives discarded, and fixes to apply.

Record the current HEAD SHA before making any changes: `git rev-parse HEAD` (needed for second-pass scoping in Step 6 — this SHA captures the state before all fixes across Steps 4-5).

Before making any edits, check if there are pre-existing staged or unstaged changes (`git status --porcelain`). If so, stash everything with `git stash push --include-untracked -m "ralphex: pre-existing changes"` to ensure a clean working tree and index. This prevents unrelated files from being committed during auto-commit. After the review pipeline completes (end of Step 6 or earlier exit), restore them with `git stash pop --index`.

Discover test/lint commands from project files (Makefile, package.json, CI config, CLAUDE.md). Run them once as a baseline before applying any fixes — record which tests/lint checks already fail. Fix all confirmed issues and re-run tests/lint. If a NEW failure appears (not in the baseline), retry the fix once with a different approach. If still failing, revert that fix, classify the issue as a known limitation, and report it. If no test/lint commands are discoverable, note this in the report.

Stage changes (`git add` specific files — only the files you modified) and commit automatically: use a single-line `git commit -m "fix: address review findings"` or for multi-line messages, write to a temp file first then `git commit -F /tmp/ralphex-commit-msg.txt`. Avoid heredoc subshells in git commit — they trigger permission prompts.

Steps 2-4 run EXACTLY ONCE with all 5 agents. Proceed to Step 5.

## Step 5: Codex Cross-Review Loop (if fixes were applied)

First verify codex is available: run `which codex`. If codex is not installed, skip this step and proceed to Step 6 with a note that codex cross-review was skipped.

This step runs iteratively — codex reviews, you evaluate and fix, codex reviews again until clean. Maximum 3 iterations.

**Iteration loop:**

5a. Run codex (omit `-m` to use the model from codex config):

```
codex exec -c model_reasoning_effort=xhigh "Review the code changes on this branch for bugs, security issues, and logic errors. Run git diff {base}...HEAD to see changes. Read source files for context. Report: file:line, issue, impact, fix. If no issues: No issues found."
```

Note: replace `{base}` with the actual base branch. If codex returns an authentication or model error (e.g. "model is not supported"), skip this step entirely and proceed to Step 6 with a note — do NOT try alternative model names.

5b. Evaluate codex output — for EACH finding, read the code and trace the flow:

- **Valid issues** — fix them, run tests/linter to verify. Do NOT commit yet. Go to 5c.
- **All findings invalid** — explain why each is invalid (intentional design, already mitigated, misunderstood context). Go to 5c.
- **Codex explicitly reports "No issues found"** — if there are uncommitted fixes (files were modified by fixes — check with `git status --porcelain`; safe because pre-existing changes were stashed in Step 4), stage and commit automatically with message `"fix: address codex review findings"`. Proceed to Step 6.
- **Empty or error output** (codex crashed/timed out) — retry once. If still empty, skip remaining iterations and proceed to Step 6 with a note.

5c. If ALL findings in this iteration were previously dismissed in an earlier iteration (same issues, same reasoning), exit the loop — codex is cycling. If there are uncommitted fixes (files were modified by fixes — check with `git status --porcelain`; safe because pre-existing changes were stashed in Step 4), stage and commit them. Proceed to Step 6. Otherwise, re-run codex (back to 5a) with the fixes applied. When re-running after dismissed findings, append a summary of what was dismissed and why to the codex prompt so it can focus on new issues.

**Loop exit conditions** (for each: if files were modified by fixes, stage and commit them before proceeding; if no changes, skip the commit):

- Codex explicitly reports no issues → proceed to Step 6
- All findings are repeats of previously dismissed issues → proceed to Step 6
- Maximum 3 iterations reached → proceed to Step 6 with a note about remaining unresolved codex findings

## Step 6: Second Pass (if fixes were applied)

Re-launch only `quality` + `implementation` agents (2 Task calls, same message).

**Second-pass prompt modifier** — prepend to each agent's prompt, replacing the standard preamble diff line:

```
This is a second-pass review of ONLY the fix commits from Steps 4-5.
Get changes: run git diff <pre-fix-sha>..HEAD to see all fixes applied.
ONLY report issues introduced by the fixes that would cause runtime failures, data loss, or security
vulnerabilities. Ignore style, documentation, naming, and simplification issues.
Output plain text only — no markdown bold, code blocks, or headers. Use - lists.
If nothing critical found, respond: No issues found.
```

Where `<pre-fix-sha>` is the HEAD SHA recorded at the start of Step 4.

Loop rules:

- If zero issues found, report done
- If issues found and fixed: check `git status --short` before staging — if no files were actually modified, stop and report remaining issues. If the same issue recurs across consecutive iterations, try a different fix approach; if still unfixable, classify as a known limitation and stop. Otherwise stage, commit automatically, and re-run Step 6
- Maximum 3 second-pass iterations — if issues persist after 3 rounds, report remaining and stop
