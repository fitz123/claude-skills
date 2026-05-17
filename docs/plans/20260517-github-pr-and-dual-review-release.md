# Release `github-pr` and `dual-review` into claude-skills public plugin

## Overview

Migrate two existing skills into the `claude-skills` public marketplace plugin so they ship alongside the other shared skills:

1. **`github-pr`** — currently a private user-level skill at `~/.claude/skills/github-pr/` (SKILL.md + 3 bash scripts). Generic GitHub Copilot PR review loop helpers — no PII, no work-specific references. Should be available to anyone using the `claude-skills` plugin.

2. **`dual-review`** — currently inside the private `orca-claude-skills` Gitea repo at `plugins/devops/skills/dual-review/SKILL.md`. The body is generic (parallel Codex + Opus adversarial review against a base branch) and references only external plugins (`thinking-tools:ask-codex`, `plannotator-annotate`). Not bound to Orca, belongs in the public plugin.

After release, the canonical homes become `~/claude-skills/plugin/skills/{github-pr,dual-review}/` and the old copies are removed.

## Context (from discovery)

- Public plugin layout: `~/claude-skills/plugin/skills/<name>/{SKILL.md,scripts/,references/}` — `skill-vetting` already demonstrates `SKILL.md + scripts/` pattern that `github-pr` will reuse verbatim.
- Two manifests, two roles:
  - `~/claude-skills/.claude-plugin/marketplace.json` — marketplace listing (points at `./plugin`; **no version field**, no bump needed at this level).
  - `~/claude-skills/plugin/.claude-plugin/plugin.json` — actual plugin manifest, currently `version: 2.1.0`. Skills auto-discover from `plugin/skills/` but **the installed plugin cache is keyed by this version** (`~/.claude/plugins/cache/claude-skills/claude-skills/2.1.0/`). Adding new skills without bumping the version leaves users on the old cache — the existing `public-repo` skill (merged in #8) is already invisible in installed 2.1.0 caches, confirming the failure mode. Version MUST be bumped (e.g. 2.1.0 → 2.2.0) in this release.
- README at `~/claude-skills/README.md` enumerates each shipped skill with a short snippet; both new skills need their own section. (Note: README currently doesn't list `public-repo` either — this release intentionally does NOT close that gap; a separate doc-cleanup PR can.)
- Path-reference convention inside a SKILL.md that lives in this plugin: `${CLAUDE_PLUGIN_ROOT}/skills/<skill-name>/scripts/<script>.sh` (5 in-tree precedents: `docx`, `skill-vetting`, plus `md-to-pdf` / `public-repo` via a `<SKILL_DIR>` macro). NOT `${CLAUDE_PLUGIN_ROOT}/scripts/...` (no `/skills/<name>/` segment) and NOT `./scripts/...` (relative paths break — skills have no guaranteed CWD).
- CI guards on PRs against `main`:
  - **author-identity-check** — every commit's author email must end in `users.noreply.github.com`. Current local `user.email = 10243861+fitz123@users.noreply.github.com` already complies — no rebase needed.
  - **gitleaks PII/secrets scan** — github-pr scripts contain only `gh` CLI calls + GraphQL templates with literal placeholders (`OWNER`, `REPO`, `NN`, `ISO-TIMESTAMP`); dual-review SKILL.md is pure prose. Neither carries secrets.
- `dual-review` references `thinking-tools:ask-codex` and `plannotator-annotate` which live in other marketplace plugins. README must document those as prerequisites so users don't get a confusing failure on first run.
- Local source state:
  - `~/.claude/skills/github-pr/` — not git-tracked. "Move" → copy then `rm -rf`.
  - `~/ordercapital/orca-claude-skills` — separate Gitea repo on `main`, clean apart from one unrelated dirty file (`plugins/devops/skills/teamcity/tc`). Deletion of `plugins/devops/skills/dual-review/` is a separate commit on a branch + Gitea PR via the `devops:tea` skill.
- Files involved:
  - Add: `~/claude-skills/plugin/skills/github-pr/SKILL.md`
  - Add: `~/claude-skills/plugin/skills/github-pr/scripts/{poll-pr-review.sh,request-copilot-rereview.sh,resolve-all-threads.sh}` (+x)
  - Add: `~/claude-skills/plugin/skills/dual-review/SKILL.md`
  - Modify: `~/claude-skills/plugin/.claude-plugin/plugin.json` (version 2.1.0 → 2.2.0; description optionally extended)
  - Modify: `~/claude-skills/README.md` (two new skill sections)
  - Delete (post-merge): `~/.claude/skills/github-pr/` (recursive)
  - Delete (separate Gitea PR): `~/ordercapital/orca-claude-skills/plugins/devops/skills/dual-review/`

## Development Approach

- **Testing approach**: Regular — skills are documentation + bash; "tests" here are functional sanity checks (executable bit, shellcheck, manifest discovery, CI passes).
- Each task = one logical unit, fully complete and verified before the next.
- Author-identity must be preserved on every commit in `~/claude-skills` (CI enforces `users.noreply.github.com`).
- Never `--no-verify`; if any pre-commit/CI hook fails, fix and recommit (don't amend a pushed commit).
- Commit boundaries on the feature branch are **for PR-review readability only** — the repo is squash-merge-only (verified), so all branch commits collapse into one commit on `main`. If independent rollback of `github-pr` vs `dual-review` ever matters, ship as two separate PRs; in this plan they ship together by design.
- Don't delete the user-level `~/.claude/skills/github-pr/` source until the public plugin PR is merged AND the new versioned cache dir (`~/.claude/plugins/cache/claude-skills/claude-skills/2.2.0/skills/github-pr/`) exists on disk. Premature deletion strands the working setup.

## Testing Strategy

- **Lint / static**: `shellcheck` on the three migrated scripts; verify shebangs and `chmod +x` survives the copy.
- **Skill files on disk (pre-merge)**: confirm the working-tree at `~/claude-skills/plugin/skills/github-pr/` and `~/claude-skills/plugin/skills/dual-review/` contains the expected SKILL.md + scripts after Task 1/2 edits — verified by `ls` and a `rg` for residual `~/.claude/skills/...` references. **Do NOT test "skill resolution" pre-cleanup**: while the user-level copy at `~/.claude/skills/github-pr/` exists, every `github-pr` invocation resolves to user-level (shadow), which makes plugin-resolution unverifiable until Post-Completion step 4.
- **CI**: PR against `~/claude-skills` `main` must pass `author-check` + `gitleaks`.
- **Manual smoke** (post-merge, in Task 5): run `bash ~/.claude/plugins/cache/claude-skills/claude-skills/2.2.0/skills/github-pr/scripts/poll-pr-review.sh` (no args; expect usage exit) to confirm scripts are executable from the new cache path.
- **End-to-end skill resolution** (post-cleanup, in Post-Completion step 5): only after the user-level copy is removed, verify `github-pr` resolves to the plugin and `${CLAUDE_PLUGIN_ROOT}` expansion works.
- No e2e tests — this project has none and the scripts are thin wrappers over `gh` CLI.

## Progress Tracking

- Mark each checkbox `[x]` immediately on completion.
- Newly discovered subtasks get `➕` prefix; blockers `⚠️` prefix.
- If a CI rule surfaces an unanticipated requirement (e.g. SKILL.md schema), update plan, don't paper over.

## Solution Overview

Branch off `main` in `~/claude-skills`, add both skills + manifest version bump + README updates, push, open PR via `gh`, iterate with Copilot reviewer using the `github-pr` skill we're shipping (dogfood). Once merged, clean up the two source locations: `rm -rf` the user-level `github-pr`, and open a separate Gitea PR via `devops:tea` against `orca-claude-skills` to remove its `dual-review` dir with a pointer in the commit message to the public plugin.

Key decision: ship as one PR. The repo is **squash-merge-only** (verified: `mergeCommitAllowed:false, rebaseMergeAllowed:false, squashMergeAllowed:true`), so any commit boundaries on the feature branch collapse into one commit on `main` — there is no post-merge revertable-independently win from splitting. The PR is still split into 4 commits **for review readability** (github-pr / dual-review / version-bump+README) so each commit's diff is focused, but the rationale stops at PR-review-time.

## Technical Details

- Branch name: `feat/github-pr-and-dual-review` off `origin/main`.
- Commit 1: `feat(github-pr): add Copilot-aware PR review loop skill` — new dir + scripts + SKILL.md path rewrites.
- Commit 2: `feat(dual-review): add Codex+Opus parallel adversarial review skill` — new dir + plannotator/Agent fixes.
- Commit 3: `chore: bump plugin version to 2.2.0` — bumps `plugin/.claude-plugin/plugin.json` version field (and optionally extends the description). Mirrors prior chore-bump commits in the repo. **Required for installed caches to pick up the new skills.**
- Commit 4: `docs(readme): document github-pr and dual-review skills` — README additions.
- Squash merge collapses all four into one commit on `main`; commit boundaries are for PR review only.
- README sections mirror existing pattern (heading link to SKILL.md, 2–3 line description, one usage example). For `dual-review`, explicitly list the two prerequisite plugins (`thinking-tools` for the `ask-codex` Skill, `plannotator` for the `plannotator` CLI on PATH that the skill shells out to via Bash).
- Author identity: the existing `~/.gitconfig` `includeIf` already scopes `fitz123` noreply email to GitHub remotes — no per-commit override needed. Avoid GitHub web-suggestion-accept during the Copilot review loop, since web-flow committer would bypass local identity (CI checks `%ae` only, not `%ce`).

## What Goes Where

- **Implementation Steps** (`[ ]`): in-repo changes — file copies, README edits, branch/PR creation, CI iteration.
- **Post-Completion** (no checkboxes): cleanup of old source paths (depend on PR being merged), Gitea PR against the separate orca-claude-skills repo, optional plugin cache refresh on this machine.

## Implementation Steps

### Task 1: Stage `github-pr` skill in claude-skills

**Files:**
- Create: `~/claude-skills/plugin/skills/github-pr/SKILL.md`
- Create: `~/claude-skills/plugin/skills/github-pr/scripts/poll-pr-review.sh` (mode 0755)
- Create: `~/claude-skills/plugin/skills/github-pr/scripts/request-copilot-rereview.sh` (mode 0755)
- Create: `~/claude-skills/plugin/skills/github-pr/scripts/resolve-all-threads.sh` (mode 0755)

- [x] create branch `feat/github-pr-and-dual-review` from `origin/main` in `~/claude-skills`
- [x] `cp -r ~/.claude/skills/github-pr/ ~/claude-skills/plugin/skills/github-pr/`
- [x] **scan migrated SKILL.md for private/orca-only references** (mirror Task 2's scan): the source `~/.claude/skills/github-pr/SKILL.md:106` contains `For Gitea, use the \`devops:tea\` skill instead.` — `devops:tea` lives in the private orca marketplace and won't resolve for public users. Edit the bullet to drop the `devops:tea` reference: either delete the line entirely (the "When to NOT use this skill" section is fine without it), or replace with a generic pointer like "Non-GitHub PR systems (e.g. Gitea, GitLab) — this skill is GitHub-specific."
- [x] verify exec bits on all three scripts (`ls -l plugin/skills/github-pr/scripts/`)
- [x] rewrite the three path references inside `plugin/skills/github-pr/SKILL.md` (currently `~/.claude/skills/github-pr/scripts/<name>.sh`) to **`${CLAUDE_PLUGIN_ROOT}/skills/github-pr/scripts/<name>.sh`** — exact pattern, no abbreviation. Verify by grep: `rg -n '\.claude/skills/github-pr' plugin/skills/github-pr/` must return nothing after the edit.
- [x] **delete the bogus reviewer-arg example block** at SKILL.md lines 53-55 of the source (the three lines: `Or specify a different reviewer + timeout:` plus the fenced `poll-pr-review.sh <pr-number> some-other-reviewer 900` block). Verified the actual script signature is `poll-pr-review.sh <pr-number> [timeout-seconds]` only (`scripts/poll-pr-review.sh:19`), and `review_author` is hardcoded (`:25`). Do **not** alternatively "extend the script to accept a reviewer arg" — keeping scripts byte-equivalent is required by the Post-Completion scripts-only `diff -r` safety gate. Delete-only is the mandatory path.
- [x] **normalize SKILL.md frontmatter** to match the more-detailed sibling skills (`brainstorm`, `ralph-review`, `notion-annotate`, `public-repo` all declare both `argument-hint` and `allowed-tools` — `md-to-pdf` and `skill-vetting` omit them, so the convention is "recommended for action-oriented skills" rather than universal): collapse the YAML folded-scalar `description: >` into a single-line string; add `argument-hint: "[pr-number]"`; add `allowed-tools` matching what the scripts actually invoke — verified by reading the three scripts: **`Bash(gh:*)`** (every script uses `gh api` and/or `gh pr`), **`Bash(bash:*)`** (so a user can invoke `bash ${CLAUDE_PLUGIN_ROOT}/skills/github-pr/scripts/<name>.sh ...` if the +x bit ever drops), **`Bash(sleep:*)`** (poll-pr-review.sh:68 `sleep 20`, request-copilot-rereview.sh:35 `sleep 3`), **`Read`**. Do NOT add `Bash(git:*)` — `rg 'git ' scripts/` returns empty; the scripts make zero git calls. Reference `~/claude-skills/plugin/skills/ralph-review/SKILL.md` frontmatter for exact YAML shape.
- [x] run `shellcheck` on the three scripts. **Do NOT modify the script bodies** — the Post-Completion scripts-only `diff -r` gate requires byte-for-byte equivalence with the user-level source. Expected (verified): `resolve-all-threads.sh:26` raises SC2016 on `$id` in single-quoted GraphQL — this is **intentional GraphQL parameter syntax**, NOT a shell-expansion bug. The variable is bound by `-f id="$id"` on line 27. Document SC2016 as expected, do not "fix" it. If other warnings surface unexpectedly, file as a follow-up — do not edit in this PR.
- [x] sanity test: `bash plugin/skills/github-pr/scripts/poll-pr-review.sh` (no args) prints usage and exits non-zero
- [x] commit: `feat(github-pr): add Copilot-aware PR review loop skill`

### Task 2: Stage `dual-review` skill in claude-skills

**Files:**
- Create: `~/claude-skills/plugin/skills/dual-review/SKILL.md`

- [x] `cp ~/ordercapital/orca-claude-skills/plugins/devops/skills/dual-review/SKILL.md ~/claude-skills/plugin/skills/dual-review/SKILL.md`
- [x] scan for orca/work-specific references (none in the body, but see the next bullet for the branch-naming gate)
- [x] **remove the `ai/` branch-prefix gate (orca-private workflow convention, blocking for public release)**: source line 34 reads `branch is main/master/develop/trunk or doesn't start with ai/`. Edit to keep refusals for the protected base branches but drop the `ai/` prefix requirement entirely. Resulting refusal list: dirty tree; in-progress git op; detached HEAD; branch is `main`/`master`/`develop`/`trunk`; no commits ahead of base. Flag any submodule pointer changes. (Public users use `feat/*`, `fix/*`, etc. — refusing them is broken-on-arrival.)
- [x] **fix the plannotator invocation — slash command can't be model-invoked**: SKILL.md line 99 says `Invoke plannotator-annotate via Skill`. The slash command at `commands/plannotator-annotate.md` has `disable-model-invocation: true` (verified), so the model **cannot** trigger it autonomously through either the Skill tool OR a slash-command invocation. The fix is to call the underlying CLI directly: replace line 99 with "Invoke `plannotator annotate <findings-file>` via Bash" — this is the same thing the slash command runs internally, and the CLI exists at `~/.local/bin/plannotator` (verified). Update the fallback wording (`Fallback if unavailable: per-finding AskUserQuestion in severity order.`) to keep the per-finding fallback for users without `plannotator` installed.
- [x] **add `Bash(plannotator:*)` to allowed-tools** so the direct-CLI invocation above is permitted without prompting.
- [x] **fix the allowed-tools list and body tool references**: remove `Agent` from `allowed-tools` (no such tool exists in the harness; only `Task` does). Update the body's `Agent(general-purpose) with the same prompt` (line 41) to `Task tool with subagent_type: "general-purpose"`, mirroring how `ralph-review` invokes subagents.
- [x] add a "Prerequisites" paragraph near the top listing the external plugins required: `thinking-tools` (for `thinking-tools:ask-codex` Skill — model-invocable) and `plannotator` plugin (for the `plannotator` CLI — model invokes via Bash; the `/plannotator-annotate` slash command is user-only by design). Include `/plugin install` hints.
- [x] confirm frontmatter description scans cleanly outside the `devops:` plugin namespace (the old name was `dual-review`, not `devops:dual-review`; no rename needed)
- [x] commit: `feat(dual-review): add Codex+Opus parallel adversarial review skill`

### Task 3: Bump plugin version + Update README.md

**Files:**
- Modify: `~/claude-skills/plugin/.claude-plugin/plugin.json` (version bump)
- Modify: `~/claude-skills/README.md`

- [x] edit `plugin/.claude-plugin/plugin.json`: bump `version` from `2.1.0` to `2.2.0`. Optionally extend the `description` field to mention GitHub PR loops + adversarial review.
- [x] commit (separately): `chore: bump plugin version to 2.2.0`
- [x] add a `### \`github-pr\`` section after `ralph-review`, ~3 lines + one fenced example invocation
- [x] add a `### \`dual-review\`` section after `github-pr`, ~3 lines + one fenced example invocation. Callout listing prerequisites: **`thinking-tools` plugin** (provides the `ask-codex` Skill — model-invokable) + **`plannotator` binary on `PATH`** (the skill invokes `plannotator annotate` via Bash; installing the `plannotator` plugin via `/plugin install plannotator@plannotator` is the recommended way to get the binary — the slash command itself has `disable-model-invocation: true` and is for user-only interactive use, but the underlying CLI is what `dual-review` actually shells out to).
- [x] update the "Workflow: From Idea to Implementation" diagram only if a natural fit; otherwise skip (these two skills are review-cycle tools, not part of the planning flow)
- [x] commit: `docs(readme): document github-pr and dual-review skills`

### Task 4: Open PR and run Copilot review loop

**Files:** (no file changes — purely PR ops)

- [ ] `git push -u origin feat/github-pr-and-dual-review`
- [ ] `gh pr create --title "feat: add github-pr and dual-review skills" --body "..."` with summary referencing this plan
- [ ] poll Copilot review using the newly-added skill itself (dogfooding) — invoke via the local working-tree path while iterating: `bash ~/claude-skills/plugin/skills/github-pr/scripts/poll-pr-review.sh <pr#>`. Chicken-and-egg note: the SKILL.md `${CLAUDE_PLUGIN_ROOT}/...` paths only resolve to the new cache version AFTER merge+restart, so during Task 4 invoke scripts by working-tree path, not by SKILL.md instruction.
- [ ] address any findings; for each round: push, run `resolve-all-threads.sh`, `request-copilot-rereview.sh`, `poll-pr-review.sh` (all from the working tree, same as above)
- [ ] confirm both CI jobs (author-check, gitleaks) pass
- [ ] merge PR once clean — **squash merge only** (verified: rebase + merge-commit disallowed in repo settings). Do NOT pick "Rebase and merge" or "Create a merge commit" in the GitHub UI; only "Squash and merge" is available anyway.

### Task 5: Verify acceptance criteria (shadow-safe ordering)

While the user-level copy at `~/.claude/skills/github-pr/` still exists, it **shadows** the plugin copy — invoking `github-pr` always resolves to user-level. So validation that targets the plugin copy must look at the cache filesystem directly, not at skill-resolution behavior. Do these checks in order:

- [ ] **before restart**: confirm the merged PR landed on `main` (`gh pr view <pr#> --json state,mergedAt`)
- [ ] **restart Claude Code** (quit + relaunch) to force the marketplace plugin to re-pull
- [ ] verify a new cache version directory exists: `ls ~/.claude/plugins/cache/claude-skills/claude-skills/2.2.0/skills/` should list **both** `github-pr/` and `dual-review/`. If only the old `2.1.0/` exists, the cache didn't refresh — investigate before going further (likely `/plugin reinstall claude-skills` needed).
- [ ] verify content sanity: `cat ~/.claude/plugins/cache/claude-skills/claude-skills/2.2.0/skills/github-pr/SKILL.md | head -3` shows the correct `name: github-pr` frontmatter
- [ ] verify scripts are executable in the cache: `ls -l ~/.claude/plugins/cache/claude-skills/claude-skills/2.2.0/skills/github-pr/scripts/` — all three +x
- [ ] verify `${CLAUDE_PLUGIN_ROOT}` substitution works: run a script via the SKILL.md-documented invocation form in a fresh CC session (after the user-level copy is removed in Post-Completion)
- [ ] README on `main` renders the two new sections correctly on github.com

### Task 6: Final cleanup and plan archive

`docs/` is intentionally **untracked** in `~/claude-skills` (`git ls-files docs/` returns empty; no `.gitignore` entry — it just lives locally). Plans don't ship to `main`. So Task 6 is a filesystem move only — no git commit.

- [ ] move plan locally: `mkdir -p ~/claude-skills/docs/plans/completed && mv ~/claude-skills/docs/plans/20260517-github-pr-and-dual-review-release.md ~/claude-skills/docs/plans/completed/`
- [ ] (no commit — `docs/` is untracked by design)
- [ ] if you ever want plans tracked, that's a separate decision and a separate PR (add `docs/plans/` to a tracked location, decide on policy for in-progress vs completed visibility)

## Post-Completion

*Items requiring external action outside `claude-skills` — no checkboxes.*

**Local source cleanup — strict ordering** (each gate must pass before the next):

1. PR is merged on `main` (verified in Task 5).
2. Claude Code restarted at least once and the new cache version `~/.claude/plugins/cache/claude-skills/claude-skills/2.2.0/skills/github-pr/` exists on disk (verified in Task 5).
3. **Scripts-only diff is empty** — `diff -r ~/.claude/skills/github-pr/scripts/ ~/.claude/plugins/cache/claude-skills/claude-skills/2.2.0/skills/github-pr/scripts/` must produce no output. The scripts are copied verbatim during Task 1, so empty diff = clean safety gate. (Don't diff the whole skill dir: SKILL.md legitimately diverges — path rewrites, frontmatter normalization, bogus-example removal — and a noisy diff defeats the gate.)
4. **Only then**: `rm -rf ~/.claude/skills/github-pr/`. After deletion, `github-pr` resolves to the plugin (no shadow), and the SKILL.md `${CLAUDE_PLUGIN_ROOT}/skills/github-pr/scripts/...` references are now exercised end-to-end.
5. Final sanity: in a fresh Claude Code session, the available-skills list shows `github-pr` (sourced from the plugin), and a script invocation via the SKILL.md path expression succeeds.

If step 2 fails (cache not refreshed), try `/plugin reinstall claude-skills`. Do NOT proceed to step 4 without step 2 passing — premature deletion strands the working setup with no `github-pr` resolvable at all.

**orca-claude-skills cleanup** (separate Gitea PR via `devops:tea` skill):
- Branch off `main` in `~/ordercapital/orca-claude-skills`.
- `git rm -r plugins/devops/skills/dual-review/`.
- Commit body: "moved to public claude-skills plugin: https://github.com/fitz123/claude-skills/tree/main/plugin/skills/dual-review".
- Open PR via `tea pr create`.
- Do NOT touch the unrelated dirty `plugins/devops/skills/teamcity/tc` file in the same branch.

**Plugin cache refresh on this machine** (if needed):
- Marketplace plugins auto-update on Claude Code restart. If the new skills don't appear after merge, `/plugin` → reinstall `claude-skills` or restart Claude Code.

**Announce / docs** (optional):
- Mention in `~/claude-skills` release notes / next CHANGELOG entry if the repo adopts one (currently it doesn't).
