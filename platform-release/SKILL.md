---
name: platform-release
description: Creates a platform-core release and updates devops-team-infra submodule. Use when user says 'platform release', 'release platform-core', 'bump core', or 'new release'.
allowed-tools:
  - Bash(git:*)
  - Bash(TERM=dumb tea:*)
  - Bash(tea:*)
  - Bash(make:*)
  - Bash(rg:*)
  - Bash(tail:*)
  - Read(*)
  - Write(*)
  - mcp__notion__notion-fetch(*)
---

# Platform Release

Creates a new platform-core release on Gitea and updates the core submodule in devops-team-infra.

## Process Reference

Canonical process doc: [Notion: platform-core updates](https://www.notion.so/239c3abf7600808fa0e3c38fdf10285d)

On every invocation, fetch this Notion page and compare against this skill. If the process has changed, update the skill before proceeding.

## Prerequisites

- Working directory: `~/ordercapital/devops-team-infra`
- `core/` submodule points to `platform-core` repo
- `tea` CLI configured with Gitea access

## Workflow

```
Progress:
- [ ] Step 1: Determine last release and new changes
- [ ] Step 2: Determine version bump (SemVer)
- [ ] Step 3: Verify build (make all)
- [ ] Step 4: Confirm release notes with user
- [ ] Step 5: Create Gitea release
- [ ] Step 6: Update devops-team-infra submodule
- [ ] Step 7: Render and verify build
- [ ] Step 8: Commit, push, create PR
```

### Step 1: Determine changes since last release

```bash
# Get latest release tag
TERM=dumb tea release list --repo ordercapital/platform-core --limit 1
```

```bash
# Pull latest main in core submodule
git -C core checkout main
git -C core pull
```

```bash
# Verify all nested submodules are at correct commits
git -C core submodule status --recursive
```

A `+` prefix means the submodule is at a different commit than recorded. Investigate before proceeding.

```bash
# List commits since last release (non-merge for changelog)
git -C core log <last-tag>..HEAD --oneline --no-merges
```

```bash
# List recent merged PRs (for PR links in changelog)
TERM=dumb tea pr list --repo ordercapital/platform-core --state closed --limit 10
```

Only include PRs merged AFTER the last release tag date.

### Step 2: Determine version (SemVer)

- **PATCH** (x.y.Z): bug fixes only
- **MINOR** (x.Y.0): new features (backward compatible)
- **MAJOR** (X.0.0): breaking changes

Ask user to confirm the version.

### Step 3: Pre-release build verification

```bash
make all
```

Must complete with no errors. Check `failed=0` in ansible output and no jsonnet validation failures.

### Step 4: Confirm release notes

Present release notes to user for approval. Follow this template:

```
## Migration Guide
<triple-backtick>
make all
<triple-backtick>

## Changelog
- [component/app] Summary https://git.ordercapital.com/ordercapital/platform-core/pulls/XX

### Notes
NA
```

When writing to the release notes file, use actual triple backticks (not the placeholder above).

Add migration commands above `make all` only if PRs require manual steps. Use `### Notes` for additional context if needed, otherwise `NA`.

### Step 5: Create Gitea release

Write release body to `/tmp/release-body-<version>.md`, then:

```bash
TERM=dumb tea release create \
  --repo ordercapital/platform-core \
  --tag <version> \
  --target <commit-hash> \
  --title "Release <version>" \
  --note-file /tmp/release-body-<version>.md
```

Get commit hash with `git -C core rev-parse HEAD`.

### Step 6: Update devops-team-infra submodule

```bash
# Create feature branch
git checkout -b chore/platform-core-<version>

# Fetch new tag and checkout in core submodule
git -C core fetch origin --tags
git -C core checkout <version>
git -C core submodule update --init --recursive
```

### Step 7: Render and verify

```bash
make all
```

Pre-release verification checklist:
- [ ] `make all` passes with no errors
- [ ] No unintended file deletions or renames in generated manifests (`git diff --stat`)
- [ ] Component versions in build output match what's expected

Review `git status` — expect changes to:
- `core` (submodule pointer)
- `k8s-apps/build/` (rendered k8s-apps manifests)
- `k8s-clusters/build/` (rendered k8s-clusters manifests)
- `bigbro/vendor/` (vendored ansible collections/roles)

### Step 8: Commit, push, create PR

Stage core and any regenerated build artifacts. Do NOT stage untracked files.

```bash
git add core <changed-build-files>

git commit -m "$(cat <<'EOF'
chore(core): bump platform-core to <version>

Release notes: https://git.ordercapital.com/ordercapital/platform-core/releases/tag/<version>
EOF
)"

git push -u origin chore/platform-core-<version>
```

```bash
TERM=dumb tea pr create \
  --title "chore(core): bump platform-core to <version>" \
  --description "$(cat <<'__PRBODY__'
## Summary
- Bump core submodule to platform-core <version>

## Release notes
https://git.ordercapital.com/ordercapital/platform-core/releases/tag/<version>

## Changes in <version>
- [component] Change summary (#PR)
__PRBODY__
)" \
  --head chore/platform-core-<version> \
  --base main
```

## Post-release

Remind user to post release link in `#devops-team-private`.

## Safety

- Never tag/release without user confirming version and release notes
- Never push directly to main — always feature branch + PR
- Only stage expected files — ignore untracked crossplane resources or local changes
- Verify `make all` passes both before release AND after submodule update
