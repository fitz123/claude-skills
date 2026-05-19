---
name: ralph-review
description: Automatic pre-PR iterative code review — 5 parallel agents (comprehensive) with critical re-check loop, code smells pass, codex external review loop (background, severity-based exit), and critical-only safety net. Each phase uses a fresh fixer subagent to verify, fix, validate, and commit. Use when reviewing branch changes before opening a PR, after implementing features, or when user says 'review' or 'ralphex'.
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
  - Bash(echo:*)
  - Bash(printf:*)
  - Read(*)
  - Write(*)
  - Edit(*)
  - Glob(*)
  - Grep(*)
  - Task(*)
---

# Ralphex — Pre-PR Multi-Agent Code Review

Adapted from [umputun/ralphex](https://github.com/umputun/ralphex) and the review pipeline in [umputun/cc-thingz/plugins/planning](https://github.com/umputun/cc-thingz/tree/master/plugins/planning). **Standalone review skill** — no plan file, no implementation, no finalize. Run it before opening a PR. Fully automatic from Step 1 onward — no user gates between phases.

**Pipeline (4 review phases, matching umputun's stage layout):**

1. **Review phase 1 — comprehensive then critical re-check** — iter 1: 5 parallel agents (quality, implementation, testing, simplification, documentation). Iter 2+: 2 agents (quality + implementation) critical-only. Loop up to 5 iterations, fresh fixer subagent after each.
2. **Review phase 2 — code smells** — 1 smells agent → fixer (single pass)
3. **Review phase 3 — codex external review** — codex runs in background, severity-based early-exit, up to 10 iterations, each iteration's findings handed to a fresh fixer
4. **Review phase 4 — critical only** — 2 agents (quality + implementation) single pass → fixer (safety net)

Every phase passes findings to a **fresh fixer subagent** that verifies, fixes, validates, and commits. The orchestrator never reads code, runs tests, or modifies files — that keeps its context lean across 5+ codex iterations.

**Invoke from the target repo.** All git commands run against CWD.

```
/ralph-review            # diff against main
/ralph-review develop    # diff against develop
```

## Severity tagging contract (load-bearing)

Every finding from every reviewer (agents AND codex) MUST be tagged:

- **CRITICAL** — crashes, data loss, security holes, race conditions
- **MAJOR** — incorrect behavior, missing error handling, broken contracts
- **MINOR** — style, doc drift, nits, optional improvements

Format each finding on its own line as: `SEVERITY: file:line — description`. Untagged findings count as MINOR. This contract drives the codex minor-only early-exit in review phase 3 and the severity filter in review phase 4.

## Progress scratchpad

A single file at `/tmp/ralphex-progress-<slug>.txt` accumulates per-phase findings, fixer responses, and decisions, where `<slug>` is the sanitized branch name derived in Step 1 (`/` and other unsafe chars replaced). Orchestrator initialises it in Step 1 and appends after every phase via simple `echo "..." >> "$PROGRESS_FILE"` (one Bash call per append, no `&&`/`;` chains).

**Codex and the fixer both read this file** so they can:

- See what was already dismissed and avoid re-flagging
- Build context cheaper than re-explaining in every prompt

The orchestrator never reads the file after Step 1 — only subagents do.

## Step 1: Gather Context

Determine the base branch (argument or default `main`). Verify it exists: `git rev-parse --verify <base>`. If missing, list available branches with `git branch -a`, suggest the closest match, and ask the user.

Check working tree state:

- `git log <base>..HEAD --oneline` — diverged commits
- `git diff <base>...HEAD --stat` — changes in diverged commits
- `git diff --stat` — unstaged
- `git diff --cached --stat` — staged
- `git status --short` — full state

Determine review scope:

- If diverged commits exist, primary scope is `git diff <base>...HEAD`. If working tree is also dirty, review only committed changes; note the dirty state.
- If no diverged commits but unstaged/staged/untracked changes exist, set `DIFF_MODE=uncommitted`.
- If nothing to review, say so and stop.

Stash pre-existing changes — but ONLY in committed-diff mode. Skip stashing entirely when `DIFF_MODE=uncommitted` (the dirty tree IS the review scope; stashing would hide it from every reviewer):

```
# Only when reviewing committed diffs:
if [ "$DIFF_MODE" != "uncommitted" ]; then
    [ -n "$(git status --porcelain)" ] && git stash push --include-untracked -m "ralphex: pre-existing"
fi
```

Restore in Step 6 with `git stash pop --index` (also conditional — see Step 6).

Capture pre-review HEAD SHA: `git rev-parse HEAD` (used in review phase 4 for second-pass diff scoping).

Derive a filesystem-safe branch slug for the progress file path — git branches can contain `/` (e.g. `feature/foo`) which would turn `/tmp/ralphex-progress-<branch>.txt` into a nested path under a non-existent directory. Replace `/` and other unsafe chars:

```
BRANCH=$(git branch --show-current)
SLUG=$(printf '%s' "$BRANCH" | tr '/ ' '__' | tr -cd '[:alnum:]._-')
PROGRESS_FILE="/tmp/ralphex-progress-${SLUG}.txt"
```

Initialise the progress file (substitute the resolved `$PROGRESS_FILE` path everywhere it appears in subsequent steps; the inner `branch:` line still records the un-sanitized branch name for human readability):

```
printf "# ralphex progress\nbranch: %s\nslug: %s\nbase: %s\nstarted: %s\npre-review SHA: %s\n\n" "$BRANCH" "$SLUG" "$BASE" "$(date -u +%FT%TZ)" "$(git rev-parse HEAD)" > "$PROGRESS_FILE"
```

Show `$PROGRESS_FILE` to the user once. From here on, all references in this skill to `/tmp/ralphex-progress-<branch>.txt` resolve to `$PROGRESS_FILE`.

## Read-only preamble (used by all review agents)

This preamble is prepended to every review-agent prompt below. With `{base}` replaced. If `DIFF_MODE=uncommitted`, swap the diff line for: "Get changes: run `git diff`, `git diff --cached`, and `git diff --stat`."

```
CRITICAL: You are a READ-ONLY reviewer. Other agents run in parallel. Do NOT run git stash/checkout/reset or any command modifying the working tree. Only git diff, git log, git show, and read tools.

Get changes: run git diff {base}...HEAD and git diff --stat {base}...HEAD.
Also check git status --short for untracked files relevant to the diff and read those.
Read the actual source files for full context — do not review from diff alone.

Read the progress file (path passed in as `$PROGRESS_FILE` — orchestrator substitutes the resolved path before sending this prompt) for prior-phase findings and fixes — re-evaluate independently; previous fixes may be incomplete.

Report pre-existing issues too — do not dismiss findings just because code existed before this branch.

Tag every finding with severity (CRITICAL/MAJOR/MINOR) and format each on its own line as:
  SEVERITY: file:line — description

For docs/CLAUDE.md findings where no specific line applies, file:section is fine (e.g. MINOR: README.md:Installation — missing --foo flag).

Plain text only. No markdown bold, no code fences, no headers. If no issues, respond with exactly: No issues found.
```

## Step 2 — Review phase 1: comprehensive then critical re-check (loop, ≤5)

Report to user: `--- Review phase 1: comprehensive ---`

Loop up to 5 iterations. **Iteration 1** dispatches 5 agents (comprehensive). **Iterations 2+** dispatch 2 agents (critical-only re-check); before each, report `--- Review phase 1: critical re-check (iteration N) ---`.

### Iteration 1 — 5 parallel agents

Send a SINGLE message with 5 Task tool calls (`subagent_type: "general-purpose"`). Do NOT use `run_in_background` for review agents — foreground tool calls in one message run in parallel and the assistant turn blocks until all return. Each prompt = preamble + the specialist block below.

**Quality** — bugs, security, error handling, races, leaks:

```
1. Logic errors - off-by-one, wrong operators, incorrect conditionals
2. Edge cases - empty inputs, nil, boundaries, concurrent access
3. Error handling - all errors checked, proper wrapping, no silent failures
4. Resource management - cleanup, leaks (file handles, connections, goroutines)
5. Concurrency - races, deadlocks, unsafe shared state
6. Security - input validation, auth, injection, secret exposure, info leakage
7. Data integrity - validation, sanitization, consistent state
```

**Implementation** — correctness, wiring, completeness:

```
1. Requirement coverage - all aspects addressed? Unhandled scenarios?
2. Correctness of approach - solving the right problem? Potential failures?
3. Wiring - components registered, routes added, handlers connected, configs updated?
4. Completeness - missing imports, unimplemented interfaces, incomplete migrations?
5. Logic flow - data flows input→output, transformations correct, state managed
6. Edge cases - empty, null, concurrent, error boundaries
Ignore style — focus on correctness and approach validity.
```

**Testing** — missing tests, fake tests, independence:

```
1. Missing tests - new code paths uncovered, untested error paths, no integration tests at boundaries
2. Fake tests - always pass, hardcoded values, verify mocks not code, conditional assertions, commented-out failures
3. Test quality - verify behavior not implementation, descriptive names, proper setup/teardown, success and failure paths
4. Test independence - no shared mutable state, no order dependencies
5. Edge case coverage - empty, nil, zero, max, concurrent, timeout
6. Coverage gaps - functions/branches uncovered
```

**Simplification** — over-engineering:

```
1. Excessive abstraction - wrappers adding nothing, factories for single impl, interface on producer side, handler→service→repo pass-through
2. Premature generalization - generic solutions for specific problems, config objects for 2 options
3. Unnecessary indirection - pass-through wrappers, excessive chaining, DTO/mapper overkill
4. Future-proofing - unused extension points, permanent feature flags, versioned internal APIs
5. Unnecessary fallbacks - unreachable paths, disabled legacy code, dual implementations, error-suppressing fallbacks
6. Premature optimization - caching rarely-accessed data, custom structures when standard collections work
```

**Documentation** — README, CLAUDE.md, plan files:

```
Check README.md — must document: new features, CLI flags, API endpoints, configs, breaking changes, new deps. Skip: internal refactoring, behavior-restoring fixes, test additions.
Check CLAUDE.md — must document: new patterns, conventions, build commands, structure changes. Skip: code following existing patterns, simple fixes.
Check plan files (docs/plans/, PLAN.md, TODO.md) if present — flag stale checkboxes.
Report what's missing, where it goes, suggested content.
```

### Iterations 2+ — critical-only re-check (2 agents)

Send a SINGLE message with 2 Task tool calls — `Quality` and `Implementation` only. Each prompt = preamble + the specialist block ABOVE + this severity filter prepended:

```
Report ONLY CRITICAL and MAJOR issues — bugs, security vulnerabilities, data loss risks, broken functionality, incorrect logic, missing critical error handling. Ignore style, minor improvements, suggestions, documentation drift. Drop any MINOR findings.

If no critical/major issues found, respond with exactly: No issues found.
```

### Collect + fixer (every iteration)

Collect findings from ALL returned agents. Build the STRICT bullet-list report:

```
### CRITICAL
- <agent>: <file>:<line> — <description>

### MAJOR
- <agent>: <file>:<line> — <description>

### MINOR
- <agent>: <file>:<line> — <description>

Total: N findings (C critical, M major, m minor)
```

Rules:

- Skip a severity heading if empty.
- For critical-only iterations (2+), drop MINOR entirely.
- Merge dupes across agents: if two agents reported the same `file:line` + same root cause, one bullet with agents joined by `+` (e.g. `quality+implementation: main.go:12 — ...`).
- Preserve agent attribution (don't rewrite as "agents").

**If all agents responded "No issues found":** append `echo "review phase 1 iter N: clean" >> <PROGRESS_FILE>`, report `Review phase 1: clean`, and proceed to Step 3.

Otherwise append findings to progress, show a compact list to the user, then **spawn ONE fixer subagent** (Task, foreground, `general-purpose`). Use the fixer prompt below with `<COMMIT_MSG>` = `"fix: address review phase 1 findings"`. After fixer returns, show its `FIXES:` block, report `Review phase 1: iteration N fixes applied`, then loop back to the next iteration (up to 5 total).

If 5 iterations reached with findings still present, report `Review phase 1: max iterations reached, moving on`, append to progress, and proceed to Step 3.

**Retry rule (any iteration):** if any single agent fails or returns garbage, retry that agent once in a separate message. If still failing, proceed with the rest and note the gap.

## Step 3 — Review phase 2: code smells (single pass)

Report to user: `--- Review phase 2: code smells analysis ---`

Spawn 1 Task subagent (foreground, `general-purpose`) with preamble + this block:

```
Review code for style consistency, convention adherence, and code smells.

1. Project conventions - read both project-level CLAUDE.md and user-level CLAUDE.md (if present), plus any docs they reference (coding standards, style guides). Check if changed code follows them.
2. Style consistency - naming, organization, import ordering, comment style, error handling pattern, logging
3. Code smells - dead code, duplication, long functions, deep nesting, magic numbers, inconsistent abstraction levels
4. Anti-patterns - god objects, shotgun surgery, feature envy, primitive obsession

For each finding: location, what's inconsistent, project convention (cite CLAUDE.md or existing code as evidence), specific fix.
Focus on consistency with existing code, not personal preferences.
```

After the agent returns:

- If "No issues found" → report `Smells analysis: clean`, append `echo "review phase 2: clean" >> <PROGRESS_FILE>`, proceed to Step 4.
- Else: build the STRICT bullet-list report, append to progress, spawn fixer with `<COMMIT_MSG>` = `"fix: address code smells"`, show FIXES, proceed to Step 4.

No loop — single pass.

## Step 4 — Review phase 3: codex external review (background loop, ≤10)

`which codex` — if missing, report `External review: skipped (no external tool available)`, append `echo "review phase 3: skipped (no codex)" >> <PROGRESS_FILE>`, proceed to Step 5.

Report to user: `--- Review phase 3: codex external review ---`

Adversarial loop, up to 10 iterations. Codex runs in the background so the orchestrator yields its turn during the 2-5 min run — the harness fires a `<task-notification>` on completion. Do NOT poll or sleep.

### Per iteration

**4a.** Resolve `DIFF_CMD`: iteration 1 = `git diff {base}...HEAD`, subsequent = `git diff`. Build the codex prompt (substitute `<DIFF_CMD>`, `<PROGRESS_FILE>`):

```
Review code changes. Run <DIFF_CMD> to see changes. Read source files for context.
Read the progress file at <PROGRESS_FILE> for prior review iterations and fixer responses — re-evaluate independently; previous fixes may be incomplete, and previously dismissed issues may be real.

Check for: bugs, security issues, race conditions, error handling, code quality.

Tag each finding with severity:
- CRITICAL: crashes, data loss, security, races
- MAJOR: correctness issues, missing error handling, broken contracts
- MINOR: style, doc drift, nits

Format each on its own line: SEVERITY: file:line — description.
(The delimiter is an em-dash `—`, matching the rest of this pipeline's contract.)
If nothing found: NO ISSUES FOUND.
```

**4b.** Run via `Bash` tool with `run_in_background: true`:

```
codex exec -c model_reasoning_effort=xhigh "<prompt>"
```

Do NOT pin `-m` (let codex use its config default). If codex returns an auth/model error (e.g. "model is not supported"), report `Codex review: skipped (model error)`, append `echo "review phase 3: codex error — skipping remainder" >> <PROGRESS_FILE>`, proceed to Step 5 — do NOT try alternative model names.

**4c.** After the completion notification, read codex output:

- "NO ISSUES FOUND" or zero findings → report `Codex review: clean`, append `echo "review phase 3 iter N: clean" >> <PROGRESS_FILE>`, proceed to Step 5.
- Otherwise scan for `CRITICAL` or `MAJOR` markers (case-insensitive whole-word). Set `has_blocking = true` if either present, else `false`.

**4d.** Show codex findings to user (compact list).

**4e.** Spawn ONE fixer subagent (Task, foreground, `general-purpose`). Use the fixer prompt below with codex output as `<FINDINGS_REPORT>` and `<COMMIT_MSG>` = `"fix: address codex review findings"`. Show FIXES to user.

**4f.** Decide:

- `has_blocking = false` (minor-only or no blocking findings) → report `Codex review: only minor findings — fixes applied, stopping loop`, append `echo "review phase 3: minor-only exit at iter N" >> <PROGRESS_FILE>`, proceed to Step 5.
- `has_blocking = true` → loop back to 4a.

If 10 iterations reached with blocking issues, report `Codex review: max iterations reached, moving on`, append `"review phase 3: max iterations reached"`, proceed.

## Step 5 — Review phase 4: critical only (single pass)

Report to user: `--- Review phase 4: critical/major only (single pass) ---`

Send a SINGLE message with 2 Task tool calls — `Quality` and `Implementation` agents (foreground). Preamble + Quality/Implementation specialist block + this scope override (substitute `<PRE_REVIEW_SHA>` from Step 1):

```
This is a final critical-only safety-net review covering all changes since pre-review HEAD.
Run git diff <PRE_REVIEW_SHA>..HEAD to see ALL fixes applied across phases 1-3.

Report ONLY CRITICAL or MAJOR issues — runtime failures, data loss, security vulnerabilities, broken functionality, incorrect logic, missing critical error handling. Ignore style, docs, naming, simplification. Drop any MINOR findings.

Tag findings: SEVERITY: file:line — description.
If nothing critical: respond exactly: No issues found.
```

After both agents return:

- If both clean → report `Review phase 4: clean`, append `echo "review phase 4: clean" >> <PROGRESS_FILE>`, proceed to Step 6.
- Else: build STRICT report (CRITICAL + MAJOR only), append to progress, spawn fixer with `<COMMIT_MSG>` = `"fix: address review phase 4 findings"`, show FIXES, proceed to Step 6.

No loop — single pass. If new issues survive review phase 4's fixer, they're recorded as known limitations in the final report.

## Fixer subagent prompt (used by all phases)

Spawn ONE Task subagent, `subagent_type: "general-purpose"`, foreground. Substitute `<FINDINGS_REPORT>`, `<PROGRESS_FILE>`, `<COMMIT_MSG>`:

```
Code review found the following issues. Verify and fix them.

Progress file: <PROGRESS_FILE> (read for prior-iteration context — earlier findings, dismissals, fixes)

FINDINGS:
<FINDINGS_REPORT>

STEP 1 — VERIFY:
For each finding, read 20-30 lines of context at file:line. Classify:
- CONFIRMED: real issue, fix it
- FALSE POSITIVE: doesn't exist or already mitigated — discard with reason

STEP 2 — BASELINE TESTS:
Discover test/lint commands from project files (Makefile, package.json, pyproject.toml, CI config, CLAUDE.md). Run them ONCE as baseline before fixing — record which already fail. If none discoverable, note it and skip validation.

STEP 3 — FIX:
Fix all confirmed issues (including adding missing tests if flagged). If a fix introduces a NEW failure (not in baseline), retry once with a different approach. If still failing, revert that fix and record as a known limitation.

STEP 4 — VALIDATE:
Re-run test/lint commands. Code MUST build and tests MUST pass (excluding baseline-pre-existing failures) before commit. NEVER commit broken code.

STEP 5 — COMMIT:
Stage by name only the files you modified. Commit with: git commit -m "<COMMIT_MSG>"
For multi-line messages, write to /tmp/ralphex-commit-msg.txt first then: git commit -F /tmp/ralphex-commit-msg.txt
Never use heredoc subshells in git commit (permission prompts).

STEP 6 — APPEND PROGRESS:
Use one echo per line, redirecting >> to <PROGRESS_FILE>. Format:
  ## <phase> fixes
  - confirmed: <count>
  - false positives: <count>
  - fixes: <one line per fix>
  - baseline-failures-preserved: <list, or none>
  - validation: <passed/failed>

STEP 7 — REPORT (mandatory, structured):
Final response MUST start with `FIXES:` on its own line, followed by:
- fixed: file:line — what changed
- false positive: description — why discarded
- known limitation: description — why unfixable

This is your return value to the parent. Be specific.
```

## Step 6 — Restore + final report

If pre-existing changes were stashed in Step 1 (only happens when `DIFF_MODE` was not `uncommitted` and the working tree was dirty): `git stash pop --index` (best-effort — surface conflicts but don't fail the run). In uncommitted mode no stash was taken, so skip this step.

Append final state to progress file (each line a separate `echo >> file`):

```
completed: <ISO>
review phase 1 iterations: <N>
review phase 3 iterations: <N>
fixes-applied: <total>
false-positives: <total>
known-limitations: <total>
```

Print a tight summary to the user:

```
✓ applied:           N
✗ false positives:   K
⚠ known limitations: U

review phase 1 (comprehensive): clean | <N> rounds → fixed | max-iter-hit
review phase 2 (smells):        clean | fixed
review phase 3 (codex):         clean | minor-only-exit (iter N) | max-iter-hit | skipped
review phase 4 (critical only): clean | fixed

pre-review SHA: <sha>
progress:       <$PROGRESS_FILE resolved in Step 1>
```

Any `⚠` → don't say "ready to PR".

## Key rules

- Each subagent gets a fresh context — orchestrator never reads code, never runs tests, never verifies findings.
- Pass the FULL findings list to the fixer — do NOT filter, dismiss, or paraphrase descriptions. The orchestrator's only allowed transform is the structural one specified in Step 2's "Collect + fixer" section: group findings under `### CRITICAL`/`### MAJOR`/`### MINOR` headings, and when two agents independently flag the same `file:line` with the same root cause, merge into a single bullet joining their names with `+` (e.g. `quality+implementation: main.go:12 — ...`). Description text, severity tags, and file:line locations stay verbatim — the merge changes only the agent attribution prefix.
- All `subagent_type` values are `general-purpose` — the prompt provides the specialization.
- Review agents (review phases 1, 2, 4): `run_in_background: false` (or omit) — they parallelize via single-message dispatch and the parent turn blocks until all return.
- Codex (review phase 3): `run_in_background: true` — frees the orchestrator turn during the 2-5 min run; harness fires a completion notification.
- Severity tags are load-bearing — they drive the codex minor-only exit. Don't skip them.
- All progress-file appends use single-command `echo >> file` (no `&&`/`;`/`|` chains, no heredocs in compounds).
- Fully automatic — no AskUserQuestion calls between phases. The pipeline runs end-to-end.
