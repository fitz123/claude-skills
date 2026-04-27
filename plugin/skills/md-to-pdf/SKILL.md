---
name: md-to-pdf
description: Convert Markdown files to clean A4 PDFs for sharing. Supports Mermaid diagrams via pre-render (mmdc) + SVG inline step.
---

# Markdown → PDF (simple, reliable)

Goal: take a `.md` file from a repo and produce a good-looking PDF.

## Path Resolution

`<SKILL_DIR>` = `${CLAUDE_PLUGIN_ROOT}/skills/md-to-pdf`

## Quick Reference

- Converter: `md-to-pdf` (npm global)
- Mermaid pre-render: `mmdc` (`@mermaid-js/mermaid-cli`)
- SVG inliner: `<SKILL_DIR>/scripts/inline-svg.py`
- Styles: `<SKILL_DIR>/assets/pdf-style.css`
- Mermaid config: `<SKILL_DIR>/assets/mermaid-config.json`
- Optional validator (for untrusted markdown): `<SKILL_DIR>/scripts/validate-md.sh`

---

## Default flow (3 steps)

### Step 1 — Optional validation (only when needed)

Use validator only for **untrusted/external** markdown.
For trusted repo docs, skip this step.

```bash
bash <SKILL_DIR>/scripts/validate-md.sh <input.md>
```

### Step 2 — Pre-process Mermaid (only if file has ```mermaid)

If the file has Mermaid blocks, run:

```bash
WORKDIR=$(mktemp -d)
cp <input.md> "$WORKDIR/input.md"

# 1) Mermaid blocks -> SVG files + processed markdown
mmdc -i "$WORKDIR/input.md" -o "$WORKDIR/processed.md" -e svg \
  -c <SKILL_DIR>/assets/mermaid-config.json

# 2) Inline SVG into markdown (required for reliable PDF render)
python3 <SKILL_DIR>/scripts/inline-svg.py "$WORKDIR/processed.md" "$WORKDIR/final.md"

# Use $WORKDIR/final.md in Step 3
```

If there are no Mermaid blocks, use the original `<input.md>` in Step 3.

### Step 3 — Convert + quick check + deliver

```bash
md-to-pdf <source.md> \
  --stylesheet <SKILL_DIR>/assets/pdf-style.css \
  --highlight-style github \
  --pdf-options '{"format":"A4","margin":"25mm 20mm","printBackground":true}'
```

Quick sanity check:

```bash
PDF="<source.pdf>"
[[ -f "$PDF" ]] && [[ $(wc -c < "$PDF") -gt 1000 ]]
```

Then send PDF via `message` tool.

---

## Canonical command recipes

### A) Markdown without Mermaid

```bash
md-to-pdf <input.md> \
  --stylesheet <SKILL_DIR>/assets/pdf-style.css \
  --highlight-style github \
  --pdf-options '{"format":"A4","margin":"25mm 20mm","printBackground":true}'
```

### B) Markdown with Mermaid

```bash
WORKDIR=$(mktemp -d)
cp <input.md> "$WORKDIR/input.md"

mmdc -i "$WORKDIR/input.md" -o "$WORKDIR/processed.md" -e svg \
  -c <SKILL_DIR>/assets/mermaid-config.json

python3 <SKILL_DIR>/scripts/inline-svg.py "$WORKDIR/processed.md" "$WORKDIR/final.md"

md-to-pdf "$WORKDIR/final.md" \
  --stylesheet <SKILL_DIR>/assets/pdf-style.css \
  --highlight-style github \
  --pdf-options '{"format":"A4","margin":"25mm 20mm","printBackground":true}'
```

---

## Authoring rules (to keep output stable)

- Use Mermaid for diagrams (` ```mermaid `), never ASCII-art boxes.
- Keep complex tables compact (A4-friendly).
- Add manual page break when needed:

```html
<div class="page-break"></div>
```
