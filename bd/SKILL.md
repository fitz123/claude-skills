---
name: bd
description: Automatically checks and manages beads tickets at task start. Use bd to track progress, save investigation data between sessions, and manage task state. Always check existing tickets first, then update or create new ones.
allowed-tools:
  - Bash(bd:*)
  - Bash(bd-create:*)
  - Bash(bd-close:*)
  - Read(*)
  - Write(*)
  - Grep(*)
---

# BD (Beads) Issue Tracker Skill

This skill provides intelligent integration with the `bd` issue tracker for task and investigation management.

## When This Skill Activates

This skill automatically activates when:
- User starts working on a new task
- User mentions checking or updating beads/bd tickets
- Starting investigation work that needs persistence
- Working on tasks mentioned in user's CLAUDE.md instructions

## Core Workflow

### 1. Check Existing Tickets First
Always start by checking if there's already a ticket for the current task:

```bash
# List all tickets
bd list

# Search for relevant tickets
bd list                           # then search output visually or with Grep tool

# Show ticket details (basic info)
bd show <issue-id>

# Show all comments
bd comments <issue-id>
```

### 2. Create New Ticket
If no relevant ticket exists (title is REQUIRED as positional argument):

```bash
# Create with title and description
bd create "Task title" -d "Detailed description of the task"

# Create with labels
bd create "Task title" -d "Description" -l investigation,kubernetes

# Create with priority (0-4, where 0=highest)
bd create "Task title" -d "Description" -p 1

# Create with type
bd create "Bug in Vector pipeline" -d "Description" -t bug
```

**Example:**
```bash
bd create "Optimize Vector metrics pipeline" \
  -d "Investigate throughput bottlenecks in crypto-prod aggregator" \
  -p 1 \
  -l performance,investigation
```

### 3. Add Comments
Track progress and save investigation data:

```bash
# Add a single-line comment
bd comment <issue-id> "Progress update or findings"

# Add multi-line comment with heredoc
bd comment <issue-id> "$(cat <<'END'
Progress update:
- Checked Prometheus metrics
- Identified bottleneck in influx sink
- Next: adjust buffer size
END
)"

# Add comment with code snippets
bd comment <issue-id> "Found config issue: buffer_size=128Mi is too small"
```

### 4. Update Ticket
```bash
# Update priority (0-4)
bd update <issue-id> -p 2

# Update title
bd update <issue-id> --title "New updated title"

# Update description
bd update <issue-id> --description "Updated description"

# Update type
bd update <issue-id> -t feature

# Close ticket
bd close <issue-id>

# Reopen ticket
bd reopen <issue-id>
```

### 5. View Ticket Information
```bash
# Show ticket details
bd show <issue-id>

# Show all comments
bd comments <issue-id>

# List ready work (no blockers)
bd ready

# Show blocked issues
bd blocked

# View recent tickets
bd list | tail -10
```

## Best Practices

1. **Always Check First**: Before creating a new ticket, search existing ones to avoid duplicates
2. **Update Regularly**: Add comments as you make progress or discover important information
3. **Use Labels**: Tag tickets with relevant labels (investigation, bug, feature, etc.)
4. **Track Dependencies**: Use `bd dep add` to link related tickets
5. **Close When Done**: Mark tickets as closed when work is complete

## Common Commands Reference

```bash
# Status and overview
bd status                         # Show database overview
bd list                          # List all issues
bd ready                         # Show ready work (no blockers)

# Create (title is REQUIRED as positional argument)
bd create "Title" -d "Description"              # Create new issue
bd create "Title" -d "Desc" -l label1,label2    # With labels
bd create "Title" -d "Desc" -p 1                # With priority (0-4)
bd create "Title" -d "Desc" -t bug              # With type

# Update and manage
bd update <id> -p 2               # Update priority
bd update <id> --title "New"      # Update title
bd close <id>                     # Close issue
bd reopen <id>                    # Reopen issue

# Comments and details
bd comment <id> "text"            # Add comment
bd comments <id>                  # View all comments
bd show <id>                      # Show ticket details

# Labels and organization
bd label add <id> <label>         # Add label
bd label list                     # List all labels

# Dependencies
bd dep add <id> <blocked-by-id>   # Add dependency
bd dep list <id>                  # List dependencies
```

## Integration with Claude Code Workflow

This skill helps maintain context across Claude Code sessions by:
- Storing investigation findings in ticket comments
- Tracking multi-step tasks with dependencies
- Recording decisions and rationale
- Maintaining history of attempted solutions

## Tips

- Use ticket IDs in Claude Code conversations for reference
- Store code snippets, config findings, and URLs in comments
- Link related tickets with dependencies to track complex work
- Review `bd show <id>` output to recall context from previous sessions
