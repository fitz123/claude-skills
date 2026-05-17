# Extend `dual-review` → `multi-review` with Gemini as a third reviewer

## Overview

Add Gemini as a third parallel reviewer to the existing `dual-review` skill in the public `claude-skills` plugin, and rename the skill to `multi-review` to reflect the broader reviewer pool. Ship a new sibling skill `ask-gemini` (mirrors `thinking-tools:ask-codex`) that wraps the local `gemini` CLI; `multi-review` invokes all three reviewers in parallel (Codex via `thinking-tools:ask-codex`, Opus via a fresh `Task` subagent, Gemini via the new `claude-skills:ask-gemini`).

Why: more independent eyes catch more material findings, and the three CLI models have meaningfully different prior distributions on what they flag. Renaming generalizes the skill so future additions (Sonnet, Grok, etc.) don't require another rename.

Why now: dual-review just shipped publicly (PR #9, plugin 2.2.0). The pattern is fresh and easy to extend before downstream users build muscle memory on `dual-review`.

## Context (from discovery)

- **Current `dual-review`** at `~/claude-skills/plugin/skills/dual-review/SKILL.md` (frontmatter `name: dual-review`, 129 lines). Launches Codex (Skill: `thinking-tools:ask-codex`) and Opus (Task: `general-purpose` subagent) in a single message, merges JSON findings by file + overlapping lines + same root cause, "min-confidence wins", drops < 0.4. Final report names reviewers (`Codex+Opus | Codex only | Opus only`).
- **`thinking-tools`** plugin at `~/.claude/plugins/cache/umputun-cc-thingz/thinking-tools/1.2.0/skills/` ships `ask-codex`, `dialectic`, `root-cause-investigator` — **no `ask-gemini`**. Owner is the same user, but the new skill lives in `claude-skills` per the decision in planning, so `multi-review` invokes `claude-skills:ask-gemini` rather than a sibling-plugin skill. (Keeps the Gemini-CLI dependency declared in the same plugin that needs it.)
- **`ask-codex` reference shape**: `allowed-tools: Bash, Read, Grep, Glob`, slug `ask-codex`, body walks: check availability (`which codex`) → build context → construct prompt → invoke `codex` CLI → return findings.
- **Gemini CLI** at `/opt/homebrew/bin/gemini`. Non-interactive: `gemini -p "<prompt>"` or stdin. Read-only review mode: `--approval-mode plan`. Default model auto-selected; `-m <model>` to override.
- **Repo conventions** (verified during the prior PR): plugin version bump (`plugin/.claude-plugin/plugin.json` `version`) required for installed caches to refresh. Squash-merge-only. CI: `author-identity` + `gitleaks`. Branch name pattern: `feat/...` or short kebab descriptor.
- **README pattern**: `~/claude-skills/README.md` has one `### \`<skill>\`` section per shipped skill with a 2–3 line description + a fenced example. `dual-review` is currently at lines ~49–60 (with the plannotator prerequisite callout).
- **Plugin layout**: `plugin/skills/<name>/SKILL.md` is the canonical path. Scripts (if any) live under `plugin/skills/<name>/scripts/` and are referenced via `${CLAUDE_PLUGIN_ROOT}/skills/<name>/scripts/<script>` — `ask-gemini` won't need scripts (it's a pure-prompt-template skill like `ask-codex`).
- **Decisions confirmed in planning**:
  1. Rename `dual-review` → `multi-review` (dir + frontmatter `name:`; activation phrases include old aliases for muscle memory).
  2. `ask-gemini` ships inside `claude-skills` plugin (not `thinking-tools`).
  3. Merge rule unchanged: any-reviewer-match wins, min-confidence ≥ 0.4, but show the reviewer count in findings so user can weight.
  4. Reviewer failure handling unchanged: retry once on non-JSON, proceed with survivors, note `gap:` in final report.
  5. Testing approach: Regular — skill is markdown + light prompt wrapping, sanity-tested by invoking on a small PR after merge.

## Development Approach

- **Testing approach**: Regular. Skills don't have unit tests; "tests" here are sanity checks (CLI availability, JSON-shape sanity, merge logic against fixtures, dogfood pass on a real PR after merge).
- Each task = one logical unit, fully complete and verified before the next. Commit boundaries on the feature branch are for **PR review readability only** — repo is squash-merge-only, so commits collapse on `main`.
- Never `--no-verify`; if pre-commit/CI fails, fix and recommit.
- Don't change merge semantics in this PR (decision item #3) — same `any-reviewer-match + min-confidence ≥ 0.4`, just with 3 reviewers in the input pool.
- Preserve activation muscle-memory: keep `dual review` / `co-review` / `cross-review` as activation phrases in the new `multi-review` description so existing user habits keep working.
- Author identity: existing `~/.gitconfig` `includeIf` for `~/claude-skills` already sets `user.email = 10243861+fitz123@users.noreply.github.com` (CI-compliant) — no per-commit override needed.

## Testing Strategy

- **CLI availability check** in `ask-gemini`: `which gemini` step like `ask-codex`'s `which codex`, with clear stop-message if missing.
- **JSON-shape validation**: the adversarial review prompt mandates strict JSON output (existing dual-review prompt). After Task 3, manually test by running `gemini -p "<minimal review prompt>"` on a throwaway diff and confirming JSON parses cleanly. If it doesn't, tighten the prompt's `<output>` section.
- **Merge sanity** (after Task 3): mentally trace through three reviewer outputs with overlapping findings + one Gemini-only finding + one Gemini-missed finding. Verify the final report `reviewers:` line correctly enumerates the union and the `gap:` line marks any reviewer that died.
- **Failure mode**: simulate by temporarily renaming `gemini` binary (or running `gemini --version` after auth invalidation) — verify the skill notes `gap: Gemini` and continues with Codex+Opus.
- **CI on PR**: both `author-identity` + `gitleaks` must pass.
- **Post-merge smoke**: after PR lands + Claude Code restart picks up the new plugin version, invoke `multi-review` on a small throwaway branch in any GitHub repo; confirm all three reviewers run, findings merge, plannotator opens correctly.
- No e2e tests in the repo and none added — pattern matches `dual-review`'s testing rigor.

## Progress Tracking

- Mark each checkbox `[x]` immediately on completion (per the existing dotfiles convention).
- `➕` prefix for tasks discovered mid-implementation; `⚠️` for blockers.
- Update plan in-place if scope drifts.

## Solution Overview

Branch off `main` in `~/claude-skills`, ship five logical commits for PR-review readability (squash collapses them on merge):

1. **`feat(ask-gemini): add CLI-wrapper skill for Google Gemini`** — new `plugin/skills/ask-gemini/SKILL.md` modeled on `thinking-tools:ask-codex` (deltas explicitly noted in the SKILL.md).
2. **`refactor: rename dual-review → multi-review`** — `git mv` the directory; update frontmatter `name:` + body H1 only; defer the four body-string updates (`/tmp/dual-review-questions...`, headings, commit-msg template) to Task 3 so this commit is a minimal rename diff.
3. **`feat(multi-review): add Gemini as third reviewer`** — modify the renamed `multi-review/SKILL.md` to launch three reviewers in parallel, update merge/triage prose, update final report wording, AND finish the de-`dual-review` substring sweep that Task 2 deliberately left for here.
4. **`feat(dual-review): add legacy stub redirecting to multi-review`** — new minimal `plugin/skills/dual-review/SKILL.md` (at the path that was just renamed) that preserves the `/dual-review` slash command for one release by redirecting the model to `multi-review`.
5. **`chore: bump plugin version + update README`** — `plugin/.claude-plugin/plugin.json` 2.2.0 → 2.3.0; README replaces the `### \`dual-review\`` section with `### \`multi-review\`` and adds a `### \`ask-gemini\`` section.

Squash-merge into `main` once Copilot review + CI pass. Dogfood the just-shipped `multi-review` on a future small change to validate end-to-end.

Key design decisions (and why):
- **Three commits for two SKILL.md edits in `multi-review`**: keep the rename diff (commit 2) byte-equivalent except for `name:` + title, so the actual code-shape changes (commit 3) read cleanly. Easier to review than one big mixed commit. Trade: implementer must remember the 4-string sweep belongs in commit 3 — explicit checklist in Task 3 calls these out by line number.
- **`ask-gemini` lives in `claude-skills`, not `thinking-tools`**: keeps the Gemini-CLI dependency declared in the same plugin that needs it (multi-review) without coupling to a separate plugin's release cadence. Mild asymmetry vs ask-codex but acceptable. Self-plugin Skill resolution form (`claude-skills:ask-gemini` vs bare `ask-gemini`) is verified by smoke-test in Task 6 before merge — silent-degrade risk closed.
- **Legacy `dual-review` stub** (commit 4): activation phrases in `description:` only steer prose-fuzzy routing, not slash-command resolution. `/dual-review` would 404 after the rename without a stub. One release of transition is gentle; stub removed in v3.0.0 once muscle memory has shifted.
- **Semver 2.3.0 (minor bump)**: with the stub in place, no user-visible workflow breaks → minor bump is honest. A 3.0.0 bump would still be defensible (the underlying name DID change) but the stub makes it overkill.
- **No merge-rule changes**: 2-of-3 quorum was tempting but adds branching logic for marginal noise reduction. "Any match + show reviewer count" preserves the simpler implementation and lets the user weight findings themselves in plannotator.

## Technical Details

- **Branch name**: `feat/multi-review-add-gemini`
- **Commits**: 5 (see Solution Overview — ask-gemini, rename, Gemini-reviewer + body cleanup, dual-review stub, version+README)
- **Plugin version**: 2.2.0 → 2.3.0 (minor — stub redirect preserves `/dual-review` slash command, no breaking change)
- **`ask-gemini` SKILL.md frontmatter shape** (intentional deltas from `thinking-tools:ask-codex` template noted below — the plan says "mirror ask-codex" but tightens permission specificity and adds `argument-hint`):
  ```yaml
  name: ask-gemini
  description: Consult Google Gemini for investigation, debugging, or code review. Use when user explicitly asks to "ask gemini", "check with gemini", "gemini review", or as a parallel reviewer in multi-review. Good for second-opinion runs on diffs and quick adversarial reviews. Runs in read-only plan mode.
  argument-hint: "<question or prompt>"
  allowed-tools:
    - Bash(gemini:*)
    - Read
    - Grep
    - Glob
  ```
  Deltas from `ask-codex` (which uses `allowed-tools: Bash, Read, Grep, Glob` as a string with broad `Bash`): (a) YAML list form vs string; (b) `Bash(gemini:*)` tighter than bare `Bash`; (c) explicit `argument-hint`. All three are valid; document them as intentional rather than accidental.
- **`multi-review` description** (preserves activation phrases):
  ```
  description: Run three independent reviewers (Codex via thinking-tools:ask-codex + a fresh Opus subagent via Task + Gemini via claude-skills:ask-gemini) in parallel against the current branch, merge findings, then write all questions to a markdown file for single-pass plannotator review before applying anything. Use when user says "multi review", "/multi-review", "triple review", "dual review" (legacy), "co-review", "cross-review", "opus+codex+gemini review", or asks for a multi-reviewer code review.
  ```
- **Gemini CLI invocation pattern** (inside `ask-gemini`):
  ```bash
  gemini -p "<prompt>" --approval-mode plan
  ```
  Or via stdin if the prompt is large:
  ```bash
  echo "<prompt>" | gemini --approval-mode plan
  ```
  `--approval-mode plan` keeps Gemini in read-only mode (no file writes) — appropriate for review.
- **`multi-review` "Launch reviewers in parallel"** section grows from 2 numbered items to 3:
  ```
  Single message:
  1. Codex — invoke `thinking-tools:ask-codex` via the `Skill` tool with the prompt below.
  2. Opus — `Task` tool with `subagent_type: "general-purpose"` using the same prompt.
  3. Gemini — invoke `claude-skills:ask-gemini` via the `Skill` tool with the same prompt.

  Retry once on non-JSON. If a reviewer dies twice, proceed with survivors and note the gap.
  ```
- **`multi-review` final report** expands the reviewer-combo line — enumerate explicitly (don't use `(any two)` shorthand; implementers will write runtime-formed strings that pass through verbatim and `(any two)` is not valid):
  ```
  reviewers:   Codex+Opus+Gemini | Codex+Opus | Codex+Gemini | Opus+Gemini | Codex only | Opus only | Gemini only | none
  ```
- **No script files** for either new skill — pure markdown + prompt templates, matching the `ask-codex` pattern.
- **No path-template work** needed (no `${CLAUDE_PLUGIN_ROOT}/skills/<name>/scripts/...` references in either SKILL.md).
- **README delta**:
  - Remove `### \`dual-review\`` section.
  - Add `### \`multi-review\`` section (3 reviewers; lists `thinking-tools` + `gemini` CLI + `plannotator` as prerequisites).
  - Add `### \`ask-gemini\`` section (short — 2 lines + one fenced invocation example).

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): in-repo edits — new file, rename, edits, version bump, README, PR open.
- **Post-Completion** (no checkboxes): Copilot review iteration, squash merge, post-merge plugin cache refresh + dogfood pass, optional adoption nudge to switch `/dual-review` → `/multi-review` in any documentation that uses the old phrase.

## Implementation Steps

### Task 1: Create `ask-gemini` skill

**Files:**
- Create: `~/claude-skills/plugin/skills/ask-gemini/SKILL.md`

- [x] Create directory: `mkdir -p ~/claude-skills/plugin/skills/ask-gemini/`
- [x] Write `SKILL.md` modeled on `thinking-tools:ask-codex`. Frontmatter: `name: ask-gemini`, the description block from Technical Details, `argument-hint: "<question or prompt>"`, `allowed-tools: [Bash(gemini:*), Read, Grep, Glob]`.
- [x] Body sections (mirror ask-codex): `# Ask Gemini` heading; `## Activation Triggers` (explicit phrases); `## Workflow` with `### Step 1: Check Availability` (`which gemini` → stop if missing); `### Step 2: Build Context` (relevant files, what we tried, specific question); `### Step 3: Construct Prompt` (template); `### Step 4: Invoke Gemini` (`gemini -p "<prompt>" --approval-mode plan` — note read-only mode; mention stdin path for large prompts); `### Step 5: Process Response` (parse output, handle non-JSON if used as a strict-output reviewer).
- [x] Add a `## Use as multi-review reviewer` subsection that documents the adversarial-review prompt contract: strict JSON, severity-tagged findings, confidence scores. Reference `multi-review/SKILL.md` for the canonical prompt.
- [x] Note Gemini-specific gotchas: large-prompt handling (prefer stdin over `-p` for prompts that would hit shell ARG_MAX — macOS ARG_MAX is ~256KB), `--approval-mode plan` vs `default` semantics (model can still read files; just no write/exec — verify against `gemini --help` text when writing this), authentication via `GEMINI_API_KEY` env or `gcloud auth application-default login` (whichever the homebrew gemini CLI actually checks — verify with `gemini --help` and the CLI's auth subcommand).
- [x] Sanity test: `gemini -p "hello"` returns non-empty output; `which gemini` returns the path. (Skill itself isn't invoked yet — just verify the underlying CLI works.)
- [x] Commit: `feat(ask-gemini): add CLI-wrapper skill for Google Gemini`. Stage: `plugin/skills/ask-gemini/SKILL.md` and `docs/plans/20260517-multi-review-add-gemini.md` (plan-file Task 1 checkboxes flipped).

### Task 2: Rename `dual-review` → `multi-review` (mechanical, no body changes)

**Files:**
- Move: `~/claude-skills/plugin/skills/dual-review/` → `~/claude-skills/plugin/skills/multi-review/`
- Modify: `~/claude-skills/plugin/skills/multi-review/SKILL.md` — frontmatter `name:` and body title only

- [x] `cd ~/claude-skills && git mv plugin/skills/dual-review plugin/skills/multi-review`
- [x] Update `plugin/skills/multi-review/SKILL.md`: frontmatter `name: dual-review` → `name: multi-review`; body H1 `# Dual Review` → `# Multi Review`. **No other changes in this commit** — keep the rename diff tight and reviewable.
- [x] Verify: `rg -n 'dual-review\|dual review\|Dual Review' ~/claude-skills/plugin/skills/multi-review/SKILL.md` returns only intentional legacy-trigger mentions (none expected in this commit since description stays unchanged until Task 3). Empty is fine.
- [x] Commit: `refactor: rename dual-review → multi-review`. Stage: the `R100` rename + the two-line edit + plan-file Task 2 checkboxes.

### Task 3: Add Gemini as third reviewer in `multi-review/SKILL.md`

**Files:**
- Modify: `~/claude-skills/plugin/skills/multi-review/SKILL.md`

Goal: change reviewer count from 2 → 3 AND fully de-`dual-review` the body. (Task 2 only touched frontmatter `name:` + H1 title; Task 3 picks up everything else. Verify after editing with the regex below — expected output: exactly ONE line, the legacy `dual review` trigger in description.)

- [x] Update frontmatter `description:` to the wording in Technical Details (three reviewers; activation phrases include `multi review` / `/multi-review` / `triple review` / `dual review` (legacy) / `co-review` / `cross-review`).
- [x] Update opening paragraph (currently: "Codex (via `thinking-tools:ask-codex`) + a fresh Opus subagent review the branch in parallel."): rewrite to name three reviewers.
- [x] Update `## Prerequisites` section: add a third bullet for the Gemini CLI — note `gemini` must be on `PATH` (verified via `which gemini`); `GEMINI_API_KEY` env or `gcloud auth application-default login` for auth; `claude-skills:ask-gemini` Skill wraps the invocation. (Pin the exact Skill prefix — see Task 5 smoke test for which form actually resolves.)
- [x] Update `## Launch reviewers in parallel` numbered list from 2 → 3 items (Codex via `Skill`, Opus via `Task`, Gemini via the verified Skill form). Keep retry-once-on-non-JSON + survive-on-death semantics.
- [x] Update `## Merge and triage` "gap" report: `gap: none | Codex | Opus | Gemini | <multiple, comma-separated>`.
- [x] **De-`dual-review` the body string-by-string** — these are NOT in the rename commit (Task 2 kept them) and need explicit edits:
  - Line 84 (source): `/tmp/dual-review-questions-$RANDOM.md` → `/tmp/multi-review-questions-$RANDOM.md`.
  - Line 87 (source): `# dual-review findings — <branch> vs <base>` → `# multi-review findings — <branch> vs <base>`.
  - Line 113 (source): `Commit \`fix: address dual-review findings\`` → `Commit \`fix: address multi-review findings\``.
- [x] Update `## Write findings` template: `reviewers: Codex+Opus+Gemini` example (or any subset).
- [x] Update `## Final report` `reviewers:` line: enumerate explicitly — `Codex+Opus+Gemini | Codex+Opus | Codex+Gemini | Opus+Gemini | Codex only | Opus only | Gemini only | none`. (Don't use `(any two)` shorthand — implementers will write runtime-formed strings that pass through verbatim, and "(any two)" is not a valid string for those.)
- [x] No change to the adversarial review prompt itself — the JSON contract is reviewer-agnostic.
- [x] **Verify de-renaming complete**: `rg -n 'dual-review|dual review|Dual Review' ~/claude-skills/plugin/skills/multi-review/SKILL.md` must return **exactly one** line — the legacy `dual review` trigger in description (intentional, for muscle memory). Any other match means a stale string slipped past — fix before commit.
- [x] Commit: `feat(multi-review): add Gemini as third reviewer`. Stage: `plugin/skills/multi-review/SKILL.md` + plan-file Task 3 checkboxes.

### Task 4: Add legacy `dual-review` stub for backward compatibility

**Files:**
- Create: `~/claude-skills/plugin/skills/dual-review/SKILL.md` (new stub at the path that was just renamed)

The rename in Task 2 makes `/dual-review` resolve to nothing (slash-command lookup matches `name:` field, NOT activation phrases in `description:` — verified empirically that description-trigger fuzzy-matching is for prose suggestions, not exact-slug routing). To preserve muscle memory for one release, ship a stub skill at the old path that redirects.

- [x] `mkdir -p ~/claude-skills/plugin/skills/dual-review/`
- [x] Write a minimal `SKILL.md` with frontmatter `name: dual-review`, `description: Legacy alias — dual-review was renamed to multi-review with Gemini added as a third reviewer. Triggers preserved for muscle memory: dual review, /dual-review, co-review, cross-review, opus+codex review. Will be removed in v3.0.0.`, no `allowed-tools` (the stub doesn't run anything itself).
- [x] Body (under 20 lines): one paragraph stating "This skill has been renamed to `multi-review` and now runs three reviewers (Codex + Opus + Gemini) instead of two. Invoke `/multi-review` (or `claude-skills:multi-review` via the Skill tool) to use the new flow." Plus a one-line note: "This stub is scheduled for removal in v3.0.0 once `/dual-review` muscle memory has faded; update aliases/docs to use `/multi-review` directly."
- [x] Verify: `rg -n 'multi-review' ~/claude-skills/plugin/skills/dual-review/SKILL.md` returns at least 2 matches (the body and the description/migration note).
- [x] Commit: `feat(dual-review): add legacy stub redirecting to multi-review`. Stage: `plugin/skills/dual-review/SKILL.md` + plan-file Task 4 checkboxes.

### Task 5: Bump plugin version + update README

**Files:**
- Modify: `~/claude-skills/plugin/.claude-plugin/plugin.json`
- Modify: `~/claude-skills/README.md`

- [ ] Edit `plugin/.claude-plugin/plugin.json`: `"version": "2.2.0"` → `"version": "2.3.0"`. Optionally extend the `description` to mention "three-reviewer adversarial code review" (keep concise).
- [ ] Edit `README.md`:
  - Replace the existing `### \`dual-review\`` section with `### \`multi-review\``. New section: 2–3 line description (three reviewers: Codex + Opus + Gemini), one fenced invocation (`/multi-review`), prerequisites callout listing `thinking-tools` (provides `ask-codex` Skill), `plannotator` (`plannotator annotate` CLI invoked via Bash; slash command is user-only), and Gemini CLI on PATH (with auth via `GEMINI_API_KEY` or `gcloud auth`).
  - Add `### \`ask-gemini\`` section after `multi-review` (or in a logical spot — match the existing ordering style; consult the README structure). 2 lines + one fenced invocation example.
- [ ] Verify: `rg -n 'dual-review' ~/claude-skills/README.md` returns either zero hits or only intentional legacy-mention text. `rg -n 'multi-review\|ask-gemini' ~/claude-skills/README.md` returns the expected new sections.
- [ ] Verify: `grep '"version"' ~/claude-skills/plugin/.claude-plugin/plugin.json` shows `2.3.0`.
- [ ] Commit: `chore: bump plugin version + document multi-review and ask-gemini`. Stage: `plugin/.claude-plugin/plugin.json`, `README.md`, plan-file Task 4 checkboxes.

### Task 6: Open PR and run Copilot review loop

**Files:** (no file changes — purely PR ops)

- [ ] `cd ~/claude-skills && git push -u origin feat/multi-review-add-gemini`
- [ ] `gh pr create --title "feat: rename dual-review → multi-review, add Gemini as third reviewer" --body "<summary>"` — body should reference this plan and list the five commits.
- [ ] **Pre-merge Skill-resolution smoke test** (de-risks the silent-degrade failure mode): install the plugin locally from the working tree before merging — `cd ~/claude-skills && /plugin marketplace add /Users/ninja/claude-skills && /plugin install claude-skills@<local>` (or whatever the supported local-install incantation is; check `/plugin --help`). In a fresh CC session targeting the local install, invoke a no-op test prompt against `claude-skills:ask-gemini` via the Skill tool. If that fails, try bare `ask-gemini`. If neither works from inside `multi-review` (same plugin), pin to direct `Bash(gemini:*)` invocation in `multi-review/SKILL.md` instead of routing through the Skill tool. Document which form was verified in the PR body so future-maintainers don't have to re-derive.
- [ ] Dogfood the now-shipping `github-pr` scripts to drive the Copilot loop: `bash ~/claude-skills/plugin/skills/github-pr/scripts/poll-pr-review.sh <pr#>` (invoke via working-tree path since `${CLAUDE_PLUGIN_ROOT}` resolves to the installed 2.2.0 cache, not the 2.3.0 about to ship).
- [ ] Address Copilot findings (push fix → `resolve-all-threads.sh` → `request-copilot-rereview.sh` → `poll-pr-review.sh`).
- [ ] Confirm `author-identity` + `gitleaks` CI both pass.
- [ ] Merge — **squash only** (verified: rebase + merge-commit disallowed on this repo).

### Task 7: Verify acceptance

- [ ] Restart Claude Code so the marketplace re-pulls the new cache version: `~/.claude/plugins/cache/claude-skills/claude-skills/2.3.0/skills/` should now exist with `ask-gemini/`, `multi-review/`, AND the legacy `dual-review/` stub.
- [ ] In a fresh CC session: `/multi-review` resolves to `claude-skills:multi-review`; `/dual-review` resolves to the stub (and the stub's body redirects the model to invoke `/multi-review`); `claude-skills:ask-gemini` appears in the available-skills list.
- [ ] Smoke test: on a small throwaway branch in any GitHub repo, run `multi-review`. Confirm all three reviewers launch in parallel and produce JSON; merge logic groups findings; plannotator opens.
- [ ] Verify failure handling: temporarily set `PATH` to exclude `/opt/homebrew/bin`, re-run `multi-review`, confirm `gap: Gemini` is reported and the run completes with the surviving two.
- [ ] Verify dual-review stub flow: `/dual-review` triggers the stub, model reads the body, then invokes `/multi-review`. Time penalty acceptable for the one-release transition.
- [ ] README on `main` renders the new sections correctly on github.com.

### Task 8: Plan archive

- [ ] Decision: `docs/` IS tracked in the repo as of PR #9 (the previous plan committed to `docs/plans/20260517-github-pr-and-dual-review-release.md` and that path is visible on `main`). Two options: (a) leave this plan at its canonical untracked path (don't add it to git) — keeps PR small, plan is local-only; (b) commit it to `docs/plans/` like the previous one — publicly visible audit trail.
- [ ] Recommended: option (b) for consistency with the precedent set by PR #9. Stage `docs/plans/20260517-multi-review-add-gemini.md` into one of the existing commits (Task 1 or Task 5 is natural — same way prior subagents staged the plan file alongside their changes). No `docs/plans/completed/` directory yet; if you want one, create it as a separate decision (out of scope for this PR).

## Post-Completion

*Items requiring action outside the PR — no checkboxes.*

**Plugin cache refresh** (post-merge):
- Marketplace plugins refresh on Claude Code restart. If `2.3.0/` cache dir doesn't appear, try `/plugin reinstall claude-skills` or the marketplace-update flow.

**Documentation / muscle-memory drift**:
- Any private docs or CLAUDE.md files that reference `/dual-review` should be updated to `/multi-review` over time. The legacy `dual review` activation phrase remains in the description for at least one release so existing habits keep working.

**Future additions** (not in this PR):
- Sonnet or Grok as additional reviewers would just add a 4th/5th `### Step N` to `multi-review/SKILL.md` and (if desired) sibling `ask-sonnet` / `ask-grok` skills in `claude-skills`.
- A `--reviewers <list>` argument to opt-in/out of specific reviewers per run. Skipped in this PR (decision item: ship always-on, configurability later if there's actual demand).

**Cross-plugin coordination**:
- `thinking-tools:ask-codex` is unchanged. No PR needed against `thinking-tools`.
