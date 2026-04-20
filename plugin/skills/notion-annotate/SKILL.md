---
name: notion-annotate
description: Remote-friendly alternative to plannotator. Push a markdown file to Notion so the user can read and comment on it from any device, then pull comments back as git-review style feedback. Use when user says 'notion push', 'notion pull', 'notion-annotate', 'notion review', 'sync to notion', 'review this on notion', or is away from the terminal and wants to annotate a markdown doc.
argument-hint: "push|pull|status <file>"
allowed-tools:
  - Read(*)
  - Write(*)
  - Bash(git:*)
  - Bash(mkdir:*)
  - Bash(basename:*)
  - mcp__notion__notion-search
  - mcp__notion__notion-create-pages
  - mcp__notion__notion-update-page
  - mcp__notion__notion-fetch
  - mcp__notion__notion-get-comments
---

# Notion Annotate

Push a markdown file to Notion, let the user comment on it from anywhere, pull the comments back as git-review style feedback. The `push` / `pull` cycle is symmetric with plannotator's `annotate` — but survives the user being remote (phone, tablet, iPad).

## Subcommands

```
push <file>      # create or update a Notion page mirroring this file
pull <file>      # fetch open comments, emit as review feedback
status           # list all synced pages for the current repo
```

## One-time bootstrap (user does this manually)

1. In Notion, create a blank page titled exactly `Claude`.
2. Share it with the Notion MCP integration (Share → Add connection).

Per-repo and per-file sub-pages are auto-created under `Claude`.

## Sync state

Per repo, at `<repo-root>/.claude/notion-sync.json`. Schema:

```json
{
  "claude_root_page_id": "...",
  "project_page_id": "...",
  "pages": {
    "docs/plan.md": {
      "page_id": "...",
      "url": "https://notion.so/...",
      "last_push": "2026-04-20T10:14:30Z"
    }
  }
}
```

Create `.claude/` if missing. This file is machine-specific — if it's tracked, tell the user to add it to `.gitignore`.

## push <file>

1. `git rev-parse --show-toplevel` → repo root. Resolve `<file>` relative to repo root; that's the key.
2. Read the file contents.
3. Load or create `.claude/notion-sync.json`.
4. If `claude_root_page_id` is missing, call `notion-search` (query `"Claude"`, filters `{}`, `page_size: 5`). Pick an exact title match. If none, stop and explain the bootstrap. If multiple, ask the user to pick.
5. If `project_page_id` is missing, create a child page under the Claude root titled `<basename $(git rev-parse --show-toplevel)>` via `notion-create-pages` with `parent: {type: "page_id", page_id: <claude_root>}`.
6. If `pages[<file>]` exists: call `notion-update-page` with `page_id`, `command: "replace_content"`, `new_str: <file contents>`, `properties: {}`, `content_updates: []`. (Unused command fields still need to be passed to satisfy the schema.)
7. Else: call `notion-create-pages` with `parent: {type: "page_id", page_id: <project_page_id>}`, a single page with `properties: {title: "<basename without .md>"}` and `content: <file contents>`. Record `page_id` + `url`.
8. Update `last_push` to current UTC ISO8601. Write the sync file.
9. Print the page URL.

### Notion-flavored Markdown

The API accepts a Markdown dialect, not raw CommonMark. Basic headings, paragraphs, lists, fenced code, inline formatting, and links pass through. If a push fails or content comes out mangled, fetch the spec and retry — don't fetch it preemptively, it's a large resource:

```
ReadMcpResourceTool(server="notion", uri="notion://docs/enhanced-markdown-spec")
```

## pull <file>

1. Read `.claude/notion-sync.json`. If no entry for `<file>`, error: "Not pushed yet. Run push first."
2. Call `notion-get-comments` with `page_id`, `include_all_blocks: true`, `include_resolved: false`.
3. If the output doesn't include block-anchor text, call `notion-fetch` with `id: <page_id>`, `include_discussions: true` to correlate discussion IDs to block content.
4. Emit the feedback inline in the conversation — Claude reads its own output on the next turn. Format:

```
# Review comments on <file>

N open discussion(s).

## 1. Inline on: "<anchor text>"
**<commenter>** <timestamp>:
> comment body

> (reply) comment body

## 2. Page-level
**<commenter>** <timestamp>:
> comment body

---

Your task: address each comment above by editing <file>. After editing, run `push <file>` to re-sync so the reviewer sees the updated version. Resolved threads are not shown.
```

If zero open discussions, print "No open comments on \<file\>." and stop.

## status

Read `.claude/notion-sync.json`. If missing, print "No pages synced from this repo." Otherwise print a table: `FILE | LAST PUSH | URL`.

## Constraints

- Single Notion workspace per machine (whichever the MCP integration is connected to).
- Only comments flow back. Content edits the user makes directly in Notion are **not** picked up; pushing overwrites them. If the user wants text changes, they should leave a comment or edit the local file.
- Resolved comments are skipped. Unresolve in Notion to re-surface.
