---
name: knowledge-loader
description: Loads documents into a structured, indexed knowledge base for specialized agents. Use when importing PDFs or text into atomic knowledge files, building cross-linked concept databases, or converting course materials into retrievable agent memory.
---

# Knowledge Loader

Converts source documents into an indexed knowledge base of atomic concept files.

## Why This Approach

Monolithic context files (10-50K tokens) waste the context window — the agent loads everything even when it needs one concept. Atomic files with embeddings solve this:

- **Selective retrieval:** `memory_search` pulls only relevant concepts (~1-2K each) instead of the full corpus
- **Cross-linking via `related:`** creates a navigable graph — the agent can follow connections between concepts
- **YAML frontmatter with `keywords:`** improves embedding quality — search matches on domain-specific terms, not just prose
- **200-500 words per file** is the sweet spot for embedding models: enough context for meaningful vectors, small enough to not dilute relevance

Requires `memorySearch.extraPaths` in agent config pointing to the knowledge directory.

## Knowledge File Format

Each file in `reference/knowledge/` — one atomic concept:

```yaml
---
title: "Concept Name"
domain: systems-design
tags: [ddd, boundaries]
keywords: [bounded context, domain boundary]
related: [other-concept.md, another.md]
source: "Course Name, Lecture N"
---
```

### Required Sections
1. **Определение** — what it is (2-3 sentences)
2. **Когда применять** — concrete situations
3. **Как применять** — steps or checklist
4. **Примеры** — from source material or practice
5. **Anti-patterns** — common mistakes
6. **Связи** — prose explanation of cross-links

### Constraints
- One file = one concept (atomic)
- 200-500 words per file
- Filename = kebab-case of title: `bounded-context.md`
- `related` references only files that exist in knowledge/
- All links bidirectional: if A→B then B→A

## Pipeline

```
Progress:
- [ ] Extract text from source (PDF/text)
- [ ] Identify discrete concepts (each = separate file)
- [ ] Write files following format above
- [ ] Cross-link pass: fill `related` fields, ensure bidirectionality
- [ ] Validate: all `related` targets exist, no orphans, no duplicates
```

### Validation Script

```bash
# Check for broken cross-links
cd reference/knowledge/
for f in *.md; do
  grep -oP '(?<=- )\S+\.md' "$f" | while read ref; do
    [ ! -f "$ref" ] && echo "BROKEN: $f -> $ref"
  done
done
```

## Agent Config

```json
{
  "memorySearch": {
    "extraPaths": ["reference/knowledge"]
  }
}
```

This makes `memory_search` index and search the knowledge directory alongside memory files.
