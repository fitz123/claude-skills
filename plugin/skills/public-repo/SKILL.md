---
name: public-repo
description: Hardens a public GitHub repo against PII leakage in commit metadata and secrets in diff content. Sets squash-only merges, deploys an Author Identity CI check workflow, enables GitHub built-in secret scanning + push protection, optionally deploys a gitleaks workflow, and verifies GitHub user email-privacy + local git includeIf are in place. Use when bootstrapping a new public repo or auditing an existing one.
argument-hint: "[owner/repo]"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(jq:*)
  - Bash(mkdir:*)
  - Bash(cp:*)
  - Bash(cat:*)
  - Bash(printf:*)
  - Bash(echo:*)
  - Bash(grep:*)
  - Bash(uname:*)
  - Bash(open:*)
  - Bash(xdg-open:*)
  - Bash(rm:*)
  - Read(*)
  - Write(*)
---

# Public Repo PII Hardening

Apply a layered defense that prevents corporate/personal **email addresses** from landing in public repo commit history (author + committer fields), and blocks credentials/secrets in diff content. Display **names** are a separate concern (see note below).

## Path Resolution

`<SKILL_DIR>` = `${CLAUDE_PLUGIN_ROOT}/skills/public-repo`
Workflow asset to deploy: `<SKILL_DIR>/assets/author-identity.yml`

## When to use this skill

- Setting up a brand-new public repo
- Auditing an existing public repo (no destructive history rewrites — just forward-looking guardrails)
- After re-cloning a repo on a new machine where `~/.gitconfig` defaults to a corporate/personal email

## Background — what gets leaked, and why each layer matters

Git commits carry **author** + **committer** name+email metadata, separately from any diff content. Tools like gitleaks scan diff *content* for credentials but do **not** look at author metadata. So a commit can pass all secret scans while still publishing a corporate/personal email to a public repo's permanent history. (Names are also exposed but harder to validate generically — see "Display name" note below.)

The defenses, ordered by where they fail:

| Layer | Catches |
|---|---|
| #1 Per-clone git config (via `~/.gitconfig` `includeIf`) | Local commits made from this clone |
| #2 GitHub user "Keep my email private" toggle | Web/API commits (squash merges, edits via UI) |
| #3 Repo squash-only merges | Limits PR damage to one commit on `main` |
| #4 CI workflow `author-identity.yml` (this skill) | PR commits whose author *or committer* email isn't `@users.noreply.github.com` — blocks before merge |
| #5 GitHub built-in secret scanning + push protection | Secrets in diff content (AWS keys, tokens, etc.) — blocks pushes |
| #6 Gitleaks workflow `pii-scan.yml` | Same as #5 but extensible via custom rules + runs on PR |

Each layer alone is incomplete. The CI check is what catches a contributor on a fresh machine whose git config defaults to a real email. The secret scanners (#5/#6) cover diff *content*, complementing the author-metadata check.

**Note about GitHub display name (not covered by these layers)**: web/API squash commits use the GitHub user's *display name* (`gh api /user --jq .name`) regardless of email privacy. If your display name contains PII, change it at https://github.com/settings/profile — there's no API for this and no per-repo workaround.

## Steps

### 1. Resolve target repo

If user gave `owner/repo` as the argument, use that. Otherwise:
- Run `git remote get-url origin` from the current directory; parse the `owner/repo` from the GitHub URL (SSH or HTTPS).
- If neither, ask the user.

Validate access:
```bash
gh api /repos/<owner>/<repo> --jq '"\(.full_name) default=\(.default_branch) admin=\(.permissions.admin) viewer=\(.viewer_can_administer)"'
```
If `admin=false`, stop and tell the user — the skill needs admin to change merge settings.

### 2. Verify (or set up) layer #1: local clone identity via `~/.gitconfig` `includeIf`

The clean pattern is to use `includeIf` in `~/.gitconfig` to override identity for repos under your GitHub username, so every clone of every personal repo gets it for free. Check:

```bash
grep -A1 'hasconfig:remote.\\*\\.url:.*github\\.com.\\*<USERNAME>' ~/.gitconfig
```

(`<USERNAME>` is the GitHub username, derived from `gh api /user --jq .login`.)

If absent, **show the user** the snippet to add to `~/.gitconfig`:

```ini
[includeIf "hasconfig:remote.*.url:**github.com:<USERNAME>/**"]
	path = ~/.gitconfig-<USERNAME>
[includeIf "hasconfig:remote.*.url:**github.com/<USERNAME>/**"]
	path = ~/.gitconfig-<USERNAME>
```

…and the override file `~/.gitconfig-<USERNAME>`:

```ini
[user]
	name = <USERNAME>
	email = <USER_ID>+<USERNAME>@users.noreply.github.com
[commit]
	gpgsign = false
```

`<USER_ID>` comes from `gh api /user --jq .id`.

**Do not modify `~/.gitconfig` automatically without confirmation** — it affects every repo on the user's machine. Show the snippets and ask before writing.

After it's in place (or already present), verify by `cd`-ing into the target repo (or any clone of it) and running `git config user.email` — must end in `@users.noreply.github.com`.

### 3. Verify (and enable) layer #2: GitHub email privacy

Enabling is UI-only — no REST/GraphQL endpoint exposes the "Keep my email addresses private" toggle as of writing.

**Best-effort detection only.** `gh api /user --jq .email` returns the user's *public profile email* field, which is **not the same** as the commit-email-privacy toggle:

- A user can have `email: null` AND still have privacy off (no public email set yet).
- A user can have `email: "alugovoi@..."` AND have commit-email-privacy on (public profile email + private commit email).

So treat this as a *hint*, not proof:

```bash
gh api /user --jq 'if .email == null or .email == "" then "no public profile email (likely-but-not-certainly private commits)" else "EXPOSED public profile email: " + .email end'
```

The reliable check is to **always tell the user to confirm the UI toggle directly**, regardless of what the API hint says:

1. Open the settings page automatically (best-effort by platform):
   ```bash
   case "$(uname -s)" in
     Darwin) open https://github.com/settings/emails ;;
     Linux)  xdg-open https://github.com/settings/emails 2>/dev/null || true ;;
     *)      printf "Open this URL: https://github.com/settings/emails\\n" ;;
   esac
   ```

2. Ask the user to verify both of the following are checked:
   > 1. ☑ **Keep my email addresses private**
   > 2. ☑ **Block command line pushes that expose my email**

3. **Gate progress on user confirmation** — wait for them to reply that both are checked. Re-checking via API is unreliable; the only authoritative check is the user looking at their settings page.

Why this gate matters: without the toggle, every web/API merge to `main` will leak the user's primary email as the *new* squash commit's committer — even after layers #1, #3, and #4 are in place. The CI workflow (#4) only checks PR-time commits, not the squash commit GitHub creates on merge.

### 4. Apply layer #3: squash-only merges

```bash
gh api -X PATCH /repos/<owner>/<repo> \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F allow_squash_merge=true \
  -F squash_merge_commit_title=PR_TITLE \
  -F squash_merge_commit_message=PR_BODY \
  --jq '"allow_merge=\(.allow_merge_commit) allow_rebase=\(.allow_rebase_merge) allow_squash=\(.allow_squash_merge)"'
```

### 5. Deploy layer #4: Author Identity CI workflow

The workflow file is at `<SKILL_DIR>/assets/author-identity.yml`. Deploy via PR (never direct push to `main`):

```bash
# Working in a fresh clone or a temp clone:
git clone --depth=1 git@github.com:<owner>/<repo>.git /tmp/<repo>-setup
cd /tmp/<repo>-setup
git checkout -b ci/author-identity-check
mkdir -p .github/workflows
cp <SKILL_DIR>/assets/author-identity.yml .github/workflows/author-identity.yml
git add .github/workflows/author-identity.yml
git commit -m "ci: enforce anonymous commit author identity"
git push -u origin ci/author-identity-check

gh pr create \
  --title "ci: enforce anonymous commit author identity" \
  --body "Adds CI check that fails any PR containing commits with non-\`@users.noreply.github.com\` author emails. Prevents accidental PII leaks from local git config defaulting to a corp/personal email." \
  --base <DEFAULT_BRANCH> --head ci/author-identity-check

# Squash-merge:
gh pr merge <PR_NUMBER> --squash --delete-branch --admin
```

Cleanup the temp clone after merge:
```bash
rm -rf /tmp/<repo>-setup
```

### 6. Apply layer #5: GitHub built-in secret scanning + push protection

These are free for public repos and block secrets at commit/push time. Single API call:

```bash
gh api -X PATCH /repos/<owner>/<repo> \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled' \
  --jq '.security_and_analysis | "secret_scanning=\(.secret_scanning.status) push_protection=\(.secret_scanning_push_protection.status)"'
```

Both should report `enabled`. Push protection in particular blocks `git push` from completing if a known secret pattern is detected — much stronger than after-the-fact scanning.

### 7. (Optional) Apply layer #6: gitleaks PII & secrets workflow

If the user maintains a shared gitleaks reusable workflow (e.g., `<owner>/claude-code-bot/.github/workflows/gitleaks-reusable.yml@main`), deploy a caller workflow at `.github/workflows/pii-scan.yml`:

```yaml
name: PII & Secrets Scan

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  gitleaks:
    uses: <OWNER>/<SHARED_REPO>/.github/workflows/gitleaks-reusable.yml@main
    secrets:
      CONFIG_PAT: ${{ secrets.GITLEAKS_CONFIG_PAT }}
```

Two prerequisites:

- The reusable workflow exists in the shared repo
- The target repo has a `GITLEAKS_CONFIG_PAT` secret configured (from `gh secret set GITLEAKS_CONFIG_PAT --repo <owner>/<repo>`)

Deploy via PR (same flow as step 5): branch → PR → squash-merge with `--admin`.

If the user doesn't have a shared gitleaks reusable workflow, **skip this layer** — layer #5 (built-in secret scanning) covers the same ground for the standard secret patterns. Layer #6 only adds value if the user has custom gitleaks rules.

### 8. (Optional) Add branch protection requiring the new check

If the user wants the new CI check to be a required status check on `main`:

```bash
gh api -X PUT /repos/<owner>/<repo>/branches/<DEFAULT_BRANCH>/protection \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": false,
    "contexts": ["author-check"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": false,
  "required_linear_history": false
}
JSON
```

If the repo already has branch protection or rulesets configured, **read the current config first** and merge — don't overwrite. Use:
```bash
gh api /repos/<owner>/<repo>/branches/<DEFAULT_BRANCH>/protection > /tmp/protection-backup.json
```

### 9. Verify final state

Run all checks and report:

```bash
echo "=== Layer 1: local identity ==="
git config user.email   # must end with @users.noreply.github.com

echo "=== Layer 2: GitHub email privacy ==="
gh api /user --jq '.email // "(private)"'   # should be null/empty or noreply

echo "=== Layer 3: squash-only merges ==="
gh api /repos/<owner>/<repo> --jq '{allow_merge_commit, allow_rebase_merge, allow_squash_merge}'

echo "=== Layer 4: author-identity CI workflow ==="
gh api /repos/<owner>/<repo>/contents/.github/workflows/author-identity.yml --jq '"\(.name) sha=\(.sha[0:7])"'

echo "=== Layer 5: GitHub built-in security ==="
gh api /repos/<owner>/<repo> --jq '.security_and_analysis | "secret_scanning=\(.secret_scanning.status) push_protection=\(.secret_scanning_push_protection.status)"'

echo "=== Layer 6 (optional): gitleaks workflow ==="
gh api /repos/<owner>/<repo>/contents/.github/workflows/pii-scan.yml --jq '"\(.name) sha=\(.sha[0:7])"' 2>/dev/null \
  || echo "  not deployed (acceptable if user has no shared gitleaks reusable workflow)"

echo "=== Display name (manual fix only) ==="
gh api /user --jq '"name=\(.name) — change at https://github.com/settings/profile if it contains PII"'
```

All required layers (1–5) must show the expected state. Layer 6 is optional. If any required layer fails, report which one and stop.

## Hard rules — DO NOT

- **Do NOT modify `~/.gitconfig` without the user explicitly confirming** the snippet to add. It's a user-wide config affecting every repo.
- **Do NOT push directly to `main`** — always go through a feature branch + PR + admin-merge.
- **Do NOT force-push to `main`** to "fix" past leaks unless the user explicitly asks for cleanup of historical commits. Forward-looking hardening only by default.
- **Do NOT create PRs in repos where you don't have admin** — the merge step requires `--admin` to bypass branch protection.

## Cleanup pass (separate request only)

If the user explicitly asks to clean up the most recent leaky tip commit on `main` (not just future-proof):

1. Clone the repo, `git commit --amend --reset-author --no-edit` on the tip
2. If branch protection exists, read it (`gh api /repos/<owner>/<repo>/branches/<DEFAULT>/protection > /tmp/protection-backup.json`), build a payload with `allow_force_pushes=true`, PUT it
3. `git push origin <DEFAULT> --force-with-lease`
4. PUT the original protection back (with `allow_force_pushes=false`)
5. For repos with rulesets (modern format) instead of classic protection: `gh api -X PUT /repos/<owner>/<repo>/rulesets/<id> -f enforcement=disabled`, push, then re-set `enforcement=active`

This is destructive on a default branch — never do it without an explicit, scoped request.
