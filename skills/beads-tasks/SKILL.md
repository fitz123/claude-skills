---
name: beads-tasks
description: "Task management via Beads CLI (bd). Use when the user asks about tasks, todos, what's next, daily standup, weekly review, blockers, priorities, planning, or task dependencies."
---

# Beads Task Management

Manage Ninja's personal tasks via `bd` (beads). Use the current agent workspace; do not `cd` into another agent's workspace just to run `bd`.

## Workspace binding
Beads uses Dolt (not SQLite) and auto-discovers `.beads/` from cwd. To target a specific workspace, `cd` into it first:
- Main: `cd /Users/ninja/.minime/workspace && bd ...`
- Bot: `cd /Users/ninja/.minime/bot && bd ...`

Issue prefixes follow workspace: `workspace-*` (main), `bot-*` (bot).

## Principles

- **Always `--json`** for programmatic output
- **Source of truth = beads DB** — don't duplicate in memory files
- **Mention in daily notes** when relevant, but don't mirror full lists
- **`bd ready`** is the core command — shows unblocked, actionable work
- **Session hygiene:** after meaningful updates and before handoff, run `bd sync --json`
- **One tracker** — no markdown TODOs; reminders допустимы только как привязанные к beads-задаче и отражённые в `reference/tasks/index.md`

## PlanSuite integration (обязательно для планируемых задач)

Для задач с планированием:
1. Иметь beads task-id (`bd create` / `bd show`).
2. Вести артефакты в `reference/tasks/<task-id>/`:
   - `task_plan.md`
   - `progress.md`
   - `findings.md`
3. Обновлять задачу через `bd comments add` по чекпоинтам.
4. Держать кросслинки в `reference/tasks/index.md` (поле `Файлы`).

## CLI Fast Path (validated on 2026-02-23)

Use this command map as canonical to avoid repetitive `bd --help` calls.

If syntax fails (version drift):
1. Run targeted help once: `bd <subcommand> --help`
2. Execute corrected command
3. Patch this SKILL.md in the same session

High-frequency commands:
```bash
bd ready --json
bd list --json
bd show <id> --json
bd create "Title" -d "Description" -p 2 --json
bd update <id> -p 1 --json
bd close <id> -r "Reason" --json
bd comments add <id> "Progress note"
bd dep add <dependent> <dependency> --json
bd dep add <new-task> <origin-task> --type discovered-from --json
bd dep relate <id1> <id2> --json
bd reopen <id> -r "Reason" --json
bd sync --json
```

## Priority Scale

| Priority | Meaning | Use for |
|----------|---------|---------|
| P0 | Critical | Deadlines today/tomorrow, time-sensitive |
| P1 | Important | Active items, health, finance, overdue |
| P2 | Normal | Regular tasks, no urgency |
| P3 | Someday | Nice to have, no deadline, aspirational |

## Labels

Categorize tasks: `health`, `finance`, `family`, `personal`, `tech`, `shopping`, `travel`, `home`, `kids`, `incident` (bugs, outages, config breaks — anything that broke and needs root-cause analysis).
Use `bd label list-all` to see existing labels. Add labels with `-l "label1,label2"` on create or `bd label add <id> <label>`.

### Strategic L-label (ОБЯЗАТЕЛЬНО при создании)

Каждая задача ДОЛЖНА получить один из `L1`, `L2`, `L3`, `L4` при создании:
- **L1** — платформа, инфра, security, skills, memory, crons, workspace, баги/инциденты
- **L2** — life automation: квартира, шоппинг, здоровье, семья, финансы, витамины, путешествия
- **L3** — бизнес: кибер-архитектор, кофейня, клиенты, доход
- **L4** — R&D, эксперименты, self-improvement, autopilot, новые инструменты

Пример: `bd create "Fix cron bug" -p 1 -l "tech,L1" --json`

Strategy Navigator dashboard (`skills/strategy-nav`) считает coverage по этим label'ам. Без L-label задача попадает в fallback-классификацию по keywords — менее точную.

## Issue Types

`task` (default), `bug`, `feature`, `chore`, `epic`. For personal tasks, mostly `task`. Use `epic` for multi-step projects (e.g., "Квартира под реновацию" with subtasks).

## Commands

### Find work
```bash
bd ready --json                          # Unblocked, ready to work on (THE key command)
bd list --json                           # All open issues
bd list --overdue --json                 # Past due date
bd list --due-before tomorrow --json     # Due today or earlier
bd list -l "label" --json                # By label
bd blocked --json                        # What's stuck on dependencies
bd stale --json                          # Not updated in 30+ days
bd status                                # Project overview with counts
bd count                                 # Quick counts
```

### Search & query
```bash
bd search "query" --json                 # Full-text search (title, description, ID)
bd query "status=open AND priority<=1" --json                # Compound query
bd query "label=health OR label=finance" --json              # OR conditions
bd query "status=open AND updated>7d" --json                 # Date-relative
bd query "priority=0 AND NOT status=closed" --json           # Negation
```

Query fields: `status`, `priority`, `type`, `assignee`, `label`, `title`, `description`, `notes`, `created`, `updated`, `closed`, `parent`, `pinned`.
Date values: `7d` (7 days ago), `24h`, `2w`, `tomorrow`, `next monday`, `2026-03-15`.

### Create
```bash
bd create "Title" -d "Description" -p 2 --json                    # Standard task
bd create "Title" -p 1 --due "+3d" -l "health" --json             # Due in 3 days
bd create "Title" -p 0 --due "2026-03-01" --json                  # Specific date
bd create "Title" --defer "+1w" --json                             # Hidden from ready until next week
bd create "Title" --parent <epic-id> --json                        # Child of epic
bd create "Title" -t epic -p 1 --json                              # Create epic
bd q "Quick thought" --json                                        # Quick capture (ID only)
bd todo add "Quick thing"                                          # Lightweight TODO
```

### Update
```bash
bd update <id> -p 1 --json               # Change priority
bd update <id> --due "+2d" --json         # Set/change due date
bd update <id> -d "New desc" --json       # Update description
bd update <id> --notes "Context" --json   # Set notes
bd update <id> --append-notes "More" --json  # Append to notes
bd update <id> -l "label1,label2" --json  # Set labels
bd update <id> --status in_progress --json  # Mark in progress
bd update <id> --claim --json             # Atomic: set assignee + in_progress
```

### Close & reopen
```bash
bd close <id> --json                     # Close (done)
bd close <id> -r "Why" --json            # Close with reason
bd close <id> --suggest-next --json      # Close + show newly unblocked
bd close <id1> <id2> --json              # Close multiple at once
bd reopen <id> --json                    # Reopen
bd todo done <id>                        # Close a TODO
```

### Defer & undefer
```bash
bd defer <id> --json                     # Defer indefinitely (hidden from ready)
bd defer <id> --until "next monday" --json  # Defer until date
bd defer <id> --until "+1w" --json       # Defer for 1 week
bd undefer <id> --json                   # Restore to open
```

### Dependencies
```bash
bd dep add <A> <B> --json                              # A depends on B (B blocks A)
bd dep <B> --blocks <A> --json                         # Explicit blocker form (same meaning)
bd dep add <A> <B> --type discovered-from --json       # A discovered while doing B
bd dep add <child> <parent> --type parent-child --json # Hierarchy link
bd dep relate <A> <B> --json                           # Soft bidirectional relation
bd dep tree <id> --json                                # Visualize dependency tree
bd dep cycles --json                                   # Detect circular deps
bd dep remove <A> <B> --json                           # Remove dependency
bd children <id> --json                                # List children of epic/parent
bd blocked --json                                      # All blocked issues
```

### Comments (track progress without changing description)
```bash
bd comments <id>                         # View comments
bd comments add <id> "Progress note"     # Add comment
```

### Show details
```bash
bd show <id> --json                      # Full details + deps + audit trail
bd show <id>                             # Human-readable view
```

### Sync & maintenance
```bash
bd sync --json                           # Flush DB state to JSONL for git workflows/handoff
bd doctor --json                         # Health check (schema/hooks/deps)
bd doctor --fix --dry-run --json         # Preview auto-fixes safely
bd admin compact --dry-run --json        # Preview compaction of old closed issues
```

## Workflows

## Post-mortem Workflow

### Post-mortem (incident close)

When closing a task with label `incident`:

1. Before `bd close` — add a post-mortem comment:
```bash
bd comments add <id> "POST-MORTEM:
Root cause: <why it happened>
Impact: <what broke, how long>
Systemic fix: <what was changed to prevent recurrence — file/rule/cron/check>
Files changed: <list of modified files>"
```
2. Verify systemic fix was actually applied (not just planned)
3. Only then close: `bd close <id> -r "Fixed + post-mortem done"`

If the systemic fix hasn't been implemented yet — DON'T close. Leave open, add comment with the plan.

Anti-pattern: closing an incident without post-mortem comment. The label `incident` is the trigger — seeing it at close time = mandatory post-mortem.

### Morning Standup
Triggered daily 09:00 MSK by `beads-morning-standup` cron.
1. `bd ready --json` → what's actionable
2. `bd list --overdue --json` → overdue items
3. `bd list --due-before tomorrow --json` → today's deadlines
4. Pick top-1 priority, send to Telegram with context and next step

### Evening Review
Triggered daily 22:30 MSK by `beads-evening-review` cron.
1. `bd list --status closed --closed-after <today> --json` → what got done
2. `bd ready --json` → candidates for tomorrow
3. `bd list --overdue --json` → growing overdue list
4. Suggest tomorrow's focus, remind about bedtime

### Weekly Review
Triggered Mondays 10:00 MSK by `beads-weekly-review` cron.
1. `bd list --status closed --closed-after <7d-ago> --json` → week's results
2. `bd stale --json` → forgotten/stuck items
3. `bd list --overdue --json` → overdue backlog
4. `bd count` → stats
5. Trends, patterns, suggestions to decompose or reprioritize

### Quick capture from conversation
When Ninja mentions something to do or remember:
1. `bd q "Title" --json` or `bd create "Title" -d "context" -p <N> -l "<label>" --json`
2. If Ninja reports something broken/crashed/failed → auto-add label `incident` along with `tech`/`bug`
3. Set priority based on urgency cues
4. Add due date if mentioned
5. Confirm back: "Записал: <title> (P<N>, <label>)"

### Session-end checklist
1. Add progress note if needed (`bd comments add <id> "..."`)
2. Run `bd sync --json`
3. Run `bd ready --json` and include next actionable item in handoff

## Date Formats
- Relative: `+6h`, `+1d`, `+2w`, `tomorrow`, `next monday`
- Absolute: `2026-03-15`, ISO 8601

## Anti-patterns
- ❌ `bd edit` — opens $EDITOR, blocks agents
- ❌ Markdown TODO lists — everything goes through bd
- ❌ Forgetting `--json` — always use for parsing
- ❌ Duplicating tasks in memory files — bd is source of truth
- ❌ Skipping `bd sync --json` before handoff/session end
- ❌ Creating without priority — always set `-p`
- ❌ Closing `incident`-labeled task without POST-MORTEM comment — always do root-cause + systemic fix before close
