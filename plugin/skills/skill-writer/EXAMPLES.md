# Skill Examples

## Example 1: API Integration (Medium Freedom)

```markdown
---
name: manage-netbox
description: Manages IP addresses and network resources in NetBox. Use for IP reservations, checking availability, and network documentation.
allowed-tools:
  - Bash(curl:*)
  - Bash(jq:*)
---

# NetBox Management

## Environment

\`\`\`bash
NETBOX_URL=https://netbox.example.com
NETBOX_API_TOKEN=<your-token>
\`\`\`

## Core Operations

### List IPs in Subnet

\`\`\`bash
curl -s "$NETBOX_URL/api/ipam/ip-addresses/?parent=10.0.0.0/24" \
  -H "Authorization: Token $NETBOX_API_TOKEN" | \
  jq -r '.results[] | "\(.address) - \(.dns_name)"'
\`\`\`

### Register New IP

\`\`\`bash
curl -s -X POST "$NETBOX_URL/api/ipam/ip-addresses/" \
  -H "Authorization: Token $NETBOX_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "address": "10.0.0.50/24",
    "status": "active",
    "dns_name": "host.example.com"
  }' | jq .
\`\`\`

## Best Practices

1. Always check availability before reserving
2. Use meaningful dns_name values
3. Add descriptions for documentation
```

## Example 2: Task Skill with Arguments (Low Freedom)

```markdown
---
name: fix-issue
description: Fixes a GitHub issue by number. Use when resolving bugs or implementing issue requests.
argument-hint: "[issue-number]"
disable-model-invocation: true
allowed-tools:
  - Bash(gh:*)
  - Read(*)
---

# Fix Issue

Fix GitHub issue #$ARGUMENTS following coding standards.

## Workflow

\`\`\`
Progress:
- [ ] Read issue details
- [ ] Investigate root cause
- [ ] Implement fix
- [ ] Run tests
- [ ] Create PR referencing issue
\`\`\`

### Step 1: Read Issue

\`\`\`bash
gh issue view $0 --json title,body,labels
\`\`\`

### Step 2–5: Fix and PR

Implement the fix, run tests, then:

\`\`\`bash
gh pr create --title "Fix #$0: <summary>" --body "Closes #$0"
\`\`\`
```

## Example 3: Subagent Skill with Dynamic Context

**NOTE**: This example uses dynamic context injection syntax that cannot be shown literally in a skill file (the loader would execute it). See [REFERENCE.md](REFERENCE.md) for the injection syntax details.

```markdown
---
name: pr-summary
description: Summarizes a pull request with diff analysis. Use when reviewing or describing PRs.
context: fork
agent: Explore
allowed-tools:
  - Bash(gh:*)
---

## Context
<inject: gh pr diff>
<inject: gh pr diff --name-only>

## Task

Summarize this pull request: what changed, why, and any risks.
```

Replace each `<inject: command>` with the actual injection syntax described in REFERENCE.md.

## Example 4: Background Knowledge (Not User-Invocable)

```markdown
---
name: api-conventions
description: API design patterns for this codebase. Applied automatically when writing API endpoints.
user-invocable: false
---

When writing API endpoints:
- Use RESTful naming: plural nouns for collections
- Return `{"error": "message", "code": "ENUM"}` on failure
- Validate request body before processing
- Log request ID on every handler entry
```

## Common Patterns

### Authentication Block

```markdown
## Auth

\`\`\`bash
-H "Authorization: Bearer $TOKEN" \
-H "Content-Type: application/json"
\`\`\`
```

### Table Reference

```markdown
| Endpoint | Method | Description |
|----------|--------|-------------|
| \`/api/items\` | GET | List items |
| \`/api/items/{id}\` | PATCH | Update item |
```

### Conditional Workflow

```markdown
**Creating new?** -> Follow Creation workflow
**Editing existing?** -> Follow Edit workflow
```
