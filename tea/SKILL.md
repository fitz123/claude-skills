---
name: tea
description: Use this skill when a user asks to create, update, or manage Gitea pull requests with the `tea` CLI, including branch creation, selective commit/push, PR creation, and PR metadata updates. Apply it for repositories hosted on Gitea remotes where robust multiline PR bodies and reliable non-interactive command patterns are required.
allowed-tools:
  - Bash(TERM=dumb tea:*)
  - Bash(tea:*)
  - Bash(git:*)
  - Bash(*gitea-pr-update:*)
---

# Tea

## Preconditions

1. Verify tooling and auth.
- Run `tea --version`.
- Run `tea login list` and confirm the target login exists.

2. Verify repo context.
- Run `git status -sb`.
- Run `git remote -v`.
- Determine default base branch:
  - `git symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##'`

## Branch and Commit Flow

1. Create or switch to a task branch.
- Prefer short names: `<ticket>-<summary>`.

2. Stage only requested files.
- Use targeted add: `git add <paths...>`.
- Validate scope: `git diff --cached --name-only`.

3. Commit and push.
- Commit with concise message.
- Push with tracking: `git push -u origin <branch>`.

## PR Creation Flow (Gitea)

Use this pattern for reliable creation:

```bash
TERM=dumb tea pulls create \
  --login <login-name> \
  --repo <owner/repo> \
  --head <branch> \
  --base <base-branch> \
  --title "<title>" \
  --description "$(cat <<'__PRBODY__'
## Summary
...

## Changes
...

## Validation
...

## Scope
...
__PRBODY__
)"
```

Rules:
- Never pass literal `\\n` in `--description`.
- Always use real multiline text via heredoc command substitution.
- Prefer explicit `--login` and `--repo`.
- Prefer `TERM=dumb` for non-interactive/TTY-limited environments.
- If repo-local invocation triggers TTY/SSH issues, rerun from neutral cwd (for example `/tmp`) with explicit `--login` and `--repo`.

## PR Update (Description/Title)

`tea` has no native PR edit command. Use the `gitea-pr-update` helper script:

1. Write the new body to a unique temp file:

```bash
PRFILE=$(mktemp /tmp/tea-pr-XXXXXXXX.md)
cat > "$PRFILE" <<'__PRBODY__'
## Summary
...
__PRBODY__
```

2. Run the update:

```bash
~/.claude/skills/tea/gitea-pr-update \
  --repo <owner/repo> \
  --index <PR-number> \
  --body-file "$PRFILE"
```

To update title only or both:

```bash
~/.claude/skills/tea/gitea-pr-update \
  --repo <owner/repo> \
  --index <PR-number> \
  --title "new title" \
  --body-file "$PRFILE"
```

Rules:
- Always use `mktemp` for temp files to avoid collisions between concurrent sessions.
- The script reads Gitea URL and API token from `~/.config/tea/config.yml` automatically.
- Clean up temp files after use if desired (script cleans its own internal temp files).

## PR Comments

Add a comment to an issue or PR:

```bash
TERM=dumb tea comment <index> --repo <owner/repo> "Comment body text"
```

Rules:
- `tea comment` takes the issue/PR index directly as a positional argument — there is NO `create` subcommand.
- The comment body is the last positional argument (quoted string).
- Do NOT use `--body` flag (does not exist).

## PR Close

```bash
TERM=dumb tea pr close <index> --repo <owner/repo>
```

## PR View

View a specific PR (including closed/merged):

```bash
TERM=dumb tea pr view <index> --repo <owner/repo> --state closed
```

Note: `tea pr view <index>` without `--state` only shows open PRs. To find merged/closed PRs, add `--state closed`.

## Troubleshooting

- If `tea` asks for SSH key passphrase, ensure key is available in agent (`ssh-add`) and retry.
- If PR creation fails due missing TTY (`open /dev/tty`), retry with `TERM=dumb` and explicit `--login`/`--repo`.
- If still blocked, use explicit API fallback and then return the PR URL.
- Return the final PR URL after successful creation.

## Safety

- Do not stage unrelated files.
- Do not amend/rewrite history unless explicitly requested.
- Keep PR title scoped to the change and ticket when available.
