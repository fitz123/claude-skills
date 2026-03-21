---
name: youtrack
description: Manages YouTrack issues with required labeling. Use when creating issues (requires Operations/KPI + team labels), querying by involvement, or preparing review summaries.
allowed-tools:
  - Bash(/Users/ninja/.claude/skills/youtrack/yt-view:*)
  - Bash(/Users/ninja/.claude/skills/youtrack/yt-search:*)
---

# YouTrack API

Write tools (`yt-cmd`, `yt-create`, `yt-comment`, `yt-update`) are not in `allowed-tools` and require explicit user approval on every invocation.

## View Issue (description + all comments)

Use the `yt-view` script for the common "fetch and display" operation:

```bash
/Users/ninja/.claude/skills/youtrack/yt-view DVPS-1234
```

This fetches summary, description, state, priority, tags, links (parent/subtask/related), and all comments in a readable format.
When the skill is invoked with `view ISSUE-ID` argument, run `yt-view` directly instead of composing curl commands.

## Update Issue Fields (summary, description)

```bash
# Rename issue title
/Users/ninja/.claude/skills/youtrack/yt-update DVPS-1234 --summary "New title"

# Update description inline
/Users/ninja/.claude/skills/youtrack/yt-update DVPS-1234 --description "Short description text"

# Update description from file (preferred for multiline)
/Users/ninja/.claude/skills/youtrack/yt-update DVPS-1234 --description-file /path/to/desc.md

# Update both at once
/Users/ninja/.claude/skills/youtrack/yt-update DVPS-1234 --summary "New title" --description-file /tmp/desc.md
```

Updates issue fields via POST to the issues API. For state/priority/tags/links use `yt-cmd` instead.

## Add Comment

```bash
# Inline text
/Users/ninja/.claude/skills/youtrack/yt-comment DVPS-1234 "comment text here"

# From file (for multiline/complex comments)
/Users/ninja/.claude/skills/youtrack/yt-comment DVPS-1234 --file /path/to/comment.md
```

Adds a comment to the issue. Supports inline text or `--file` for longer content.

**Before adding a comment:** always run `yt-view ISSUE-ID` first to read existing comments. Avoid posting duplicates or repeating what's already there. Keep comments concise and factual — no filler, no restating known context.

## Execute Commands (assign, tag, link, state, priority)

```bash
# Single issue, single command
/Users/ninja/.claude/skills/youtrack/yt-cmd DVPS-1234 "Assignee gmalashikhin"

# Remove assignee
/Users/ninja/.claude/skills/youtrack/yt-cmd DVPS-1234 "remove Assignee alugovoi"

# Link as subtask
/Users/ninja/.claude/skills/youtrack/yt-cmd DVPS-1234 "subtask of DVPS-6888"

# Tag, state, priority
/Users/ninja/.claude/skills/youtrack/yt-cmd DVPS-1234 "tag Operations state In progress Priority P2"

# Combined commands (assign + link + remove self)
/Users/ninja/.claude/skills/youtrack/yt-cmd DVPS-1234 "Assignee gmalashikhin subtask of DVPS-6888 remove Assignee alugovoi"

# Multiple issues at once
/Users/ninja/.claude/skills/youtrack/yt-cmd DVPS-1234,DVPS-5678 "tag Operations Priority P3"
```

When the skill is invoked with `command ISSUE-ID "query"` argument, run `yt-cmd` directly.

## Search Issues

```bash
# Unresolved issues assigned to me
/Users/ninja/.claude/skills/youtrack/yt-search "Assignee:me #Unresolved"

# Subtasks of a parent
/Users/ninja/.claude/skills/youtrack/yt-search "subtask of: DVPS-6888 #Unresolved"

# By assignee
/Users/ninja/.claude/skills/youtrack/yt-search "Assignee:gmalashikhin #Unresolved"

# By tag and date
/Users/ninja/.claude/skills/youtrack/yt-search "tag: Operations updated: {Last week}"

# Limit results
/Users/ninja/.claude/skills/youtrack/yt-search "Assignee:me #Unresolved" --top 50
```

When the skill is invoked with `search "query"` argument, run `yt-search` directly.

## Create Issue

```bash
# With inline description
/Users/ninja/.claude/skills/youtrack/yt-create --project DVPS --summary "Fix login bug" --description "Steps to reproduce..."

# With description from file
/Users/ninja/.claude/skills/youtrack/yt-create --project DVPS --summary "Server migration" --description-file /tmp/desc.md

# With commands applied after creation (tags, assign, state, link)
/Users/ninja/.claude/skills/youtrack/yt-create --project DVPS --summary "New task" --description-file /tmp/desc.md \
  --command "tag Operations Assignee gmalashikhin subtask of DVPS-6888 state In progress"
```

When the skill is invoked with `create ...` arguments, run `yt-create` directly.

Base: `https://ordercapital.myjetbrains.com/youtrack/api`

## CRITICAL: Curl Best Practices

1. **Use `-k` flag only as fallback** - If SSL errors (exit code 35) occur, add `-k` to bypass certificate verification
2. **Always use `printenv` to capture the token** - Direct `$YOUTRACK_TOKEN` expansion fails in subshells

```bash
# CORRECT - Use printenv to reliably capture token
curl -s -H "Accept: application/json" \
  -H "Authorization: Bearer $(printenv YOUTRACK_TOKEN)" "URL"

# WRONG - These cause "blank argument" errors in Claude Code
AUTH_HEADER="Authorization: Bearer $YOUTRACK_TOKEN"
curl -s -k -H "$AUTH_HEADER" "URL"  # FAILS - token not expanded

curl -s -k -H "Authorization: Bearer $YOUTRACK_TOKEN" "URL"  # FAILS
```

## Updating Tickets - ALWAYS Fetch First

**Before updating any ticket, ALWAYS fetch current state to avoid overwriting changes:**

```bash
# 1. Fetch current state (description, comments, links, state)
/Users/ninja/.claude/skills/youtrack/yt-view DVPS-1234

# 2. Only then update fields or apply commands
/Users/ninja/.claude/skills/youtrack/yt-update DVPS-1234 --description-file /tmp/updated-desc.md
/Users/ninja/.claude/skills/youtrack/yt-cmd DVPS-1234 "state In progress"
```

## GET Single Issue

```bash
TOKEN=$(printenv YOUTRACK_TOKEN) && curl -s -k -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  "https://ordercapital.myjetbrains.com/youtrack/api/issues/DVPS-1234?fields=idReadable,summary,description"
```

## POST Create New Issue

**CRITICAL**: Use `shortName` for project reference, NOT `id`. Using `id` may create issues in wrong project.

**CRITICAL**: Tags CANNOT be added via JSON payload (causes "entity not found" error). Create issue first, then add tags via command API.

**REQUIRED LABELS** - Always include both:

1. **Type label**: `Operations` OR `KPI`
2. **Team label**: `common`, `steno`, `crypto`, `china`, `inia`, or `services`

**STATE WORKFLOW**:

- Create tickets in `In progress` state
- When user asks to close/complete/done, set to `Reviewing` state (NEVER use `Done` directly)
- `Done` state is only used after review is complete (manual action)

```bash
# 1. Create JSON payload WITHOUT tags
cat > /tmp/yt-new-issue.json << 'EOF'
{
  "project": {"shortName": "DVPS"},
  "summary": "Issue title here",
  "description": "Issue description in markdown"
}
EOF

# 2. Create the issue
TOKEN=$(printenv YOUTRACK_TOKEN)
ISSUE=$(curl -s -k -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  "https://ordercapital.myjetbrains.com/youtrack/api/issues?fields=idReadable,summary" \
  -d @/tmp/yt-new-issue.json)
echo "$ISSUE"
ISSUE_ID=$(echo "$ISSUE" | jq -r '.idReadable')

# 3. Add tags and set state via command API (combine in one command)
curl -s -k -X POST -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  'https://ordercapital.myjetbrains.com/youtrack/api/commands' \
  -d "{\"query\":\"tag Operations tag steno state In progress\",\"issues\":[{\"idReadable\":\"$ISSUE_ID\"}]}"
```

### Closing/Completing Work - Always Use Reviewing

**CRITICAL**: When user asks to "close", "complete", or "mark as done", ALWAYS set state to `Reviewing`, NOT `Done`.

```bash
# When user says "close it" or "mark as done" - set to Reviewing state
TOKEN=$(printenv YOUTRACK_TOKEN) && curl -s -k -X POST -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  'https://ordercapital.myjetbrains.com/youtrack/api/commands' \
  -d '{"query":"state Reviewing","issues":[{"idReadable":"DVPS-1234"}]}'
```

### Label Reference

| Type Labels | Team Labels |
|-------------|-------------|
| `Operations` | `steno` |
| `KPI` | `crypto` |
|  | `china` |
|  | `inia` |
|  | `common` |
|  | `services` |

### Domain Labels

| Label | Description |
|-------|-------------|
| `msk-decom` | MSK decommission and post-migration |
| `observability` | Monitoring, alerting, logging |
| `platform` | Platform and BigBro |
| `k8s` | Kubernetes platform |
| `china` | China networking |
| `networking` | Network issues |
| `security` | Security and OIDC |
| `llm` | LLM/Copilot |
| `operations` | Ad-hoc operations |

## Priority System

**CRITICAL**: YouTrack uses INVERTED priority numbering:

| Priority | Meaning | Use for |
|----------|---------|---------|
| P0 | Critical | Production outages, security incidents |
| P4 | Highest | Active/blocking work, urgent tasks |
| P3 | High | Planned work, important features |
| P2 | Normal | Regular work, standard tasks |
| P1 | Lowest | Backlog, on hold, low priority |

**Beads mapping** (when creating beads tickets from YouTrack):

- YouTrack P0 → beads priority 0 (critical)
- YouTrack P4 → beads priority 0 (critical)
- YouTrack P3 → beads priority 1 (high)
- YouTrack P2 → beads priority 2 (medium)
- YouTrack P1 → beads priority 4 (backlog)

## Commands API (Batch Operations)

Use `/api/commands` for batch updates to labels, priorities, states, etc.

**CRITICAL**: Empty `{}` response means SUCCESS. Do not treat it as an error.

```bash
TOKEN=$(printenv YOUTRACK_TOKEN)

# Add tag to multiple tickets
curl -s -k -X POST -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  'https://ordercapital.myjetbrains.com/youtrack/api/commands' \
  -d '{"query":"tag observability","issues":[{"idReadable":"DVPS-1234"},{"idReadable":"DVPS-5678"}]}'
# Returns: {} (empty object = success)

# Set priority for multiple tickets
curl -s -k -X POST -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  'https://ordercapital.myjetbrains.com/youtrack/api/commands' \
  -d '{"query":"Priority P4","issues":[{"idReadable":"DVPS-1234"},{"idReadable":"DVPS-5678"}]}'

# Combine multiple commands
curl -s -k -X POST -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  'https://ordercapital.myjetbrains.com/youtrack/api/commands' \
  -d '{"query":"tag k8s Priority P3 state In progress","issues":[{"idReadable":"DVPS-1234"}]}'
```

### Common Command Queries

| Command | Effect |
|---------|--------|
| `tag <name>` | Add tag/label |
| `untag <name>` | Remove tag/label |
| `Priority <P0-P4>` | Set priority |
| `state <name>` | Set state |
| `Type <name>` | Set issue type (e.g., `Type Task`, `Type Epic`) |
| `Assignee <login>` | Assign to user |
| `remove Assignee <login>` | Remove assignee |
| `subtask of DVPS-XXXX` | Link as subtask of parent |
| `parent for DVPS-XXXX` | Link as parent of child |

## Involvement Filters

| Filter | Description |
|--------|-------------|
| `Assignee:me` | Issues assigned to me |
| `reporter:me` | Issues I created |
| `commenter:me` | Issues I commented on |
| `updater:me` | Issues I last modified |

Combine with `or`: `(Assignee:me or reporter:me or commenter:me)`

## Date Syntax

**Critical:** Spaces required around `..`

```
updated: 2025-06-18 .. Today      # date range
updated: Today                    # today only
updated: {Last week}              # predefined
updated: {Last month}
created: {This year}
```

Predefined: `Today`, `Yesterday`, `{Last week}`, `{This week}`, `{Last month}`, `{This year}`

## State Filters

```
#Resolved      # closed issues
#Unresolved    # open issues
State: Done    # specific state
```

## Query Examples

```bash
TOKEN=$(printenv YOUTRACK_TOKEN)

# My assigned issues in date range
curl -s -k -H "Accept: application/json" -H "Authorization: Bearer $TOKEN" \
  "https://ordercapital.myjetbrains.com/youtrack/api/issues?fields=idReadable,summary,resolved&query=Assignee:me%20updated:%202025-06-18%20..%20Today&\$top=100"

# All my involvement (assigned OR reported OR commented)
curl -s -k -H "Accept: application/json" -H "Authorization: Bearer $TOKEN" \
  "https://ordercapital.myjetbrains.com/youtrack/api/issues?fields=idReadable,summary,resolved&query=(Assignee:me%20or%20reporter:me%20or%20commenter:me)%20and%20updated:%202025-06-18%20..%20Today&\$top=100"

# Only resolved issues
curl -s -k -H "Accept: application/json" -H "Authorization: Bearer $TOKEN" \
  "https://ordercapital.myjetbrains.com/youtrack/api/issues?fields=idReadable,summary,resolved&query=Assignee:me%20%23Resolved%20updated:%202025-06-18%20..%20Today&\$top=100"
```

## Response Fields

```
# Minimal
fields=idReadable,summary

# With dates
fields=idReadable,summary,created,updated,resolved

# With project and state
fields=idReadable,summary,project(shortName),State(name),resolved

# Full for reports
fields=idReadable,summary,description,project(shortName,name),created,updated,resolved,State(name),Assignee(login)
```

## Pagination

```
$top=100      # max results (up to 500)
$skip=0       # offset for paging
```

## Projects

| Short | Name |
|-------|------|
| DVPS | DevOps |
| INFRA | Infrastructure |
| DM | Data Management |
| DP | Data Pipelines |
| IS | Infrastructure Security |
| BMC | Bare Metal Configuration |
| NETOPS | netops |

## URL Encoding

| Char | Encoded |
|------|---------|
| space | `%20` |
| `:` | `%3A` (or leave as-is) |
| `#` | `%23` |
| `(` | `%28` |
| `)` | `%29` |
| `{` | `%7B` |
| `}` | `%7D` |
