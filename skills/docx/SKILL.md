---
name: editing-docx
description: Reads, edits, and exports Microsoft Word .docx files. Use when opening, filling in, modifying Word documents, templates, forms, or converting to PDF.
allowed-tools:
  - Bash(uv:*)
  - Bash(uvx:*)
  - Bash(cp:*)
---

# DOCX Editing

Read, edit, and export `.docx` files. No permanent install needed.

- Read/edit: `uv run --with python-docx`
- PDF export: `uvx docx2pdf` (uses MS Word via automation)

## Arguments

```
read <file>                                          # display contents
edit <file> '{"old":"new", ...}' [output]            # replace text
set-cell <file> <table> <row> <col> "value" [output] # set table cell
pdf <file> [output.pdf]                              # export to PDF
```

## Operations

### Read Document

```bash
uv run --with python-docx python3 ${CLAUDE_PLUGIN_ROOT}/skills/docx/scripts/docx_tool.py read "/path/to/file.docx"
```

Output: paragraphs with indices/styles, tables with row/col, content controls, headers/footers.

### Edit (Replace Text)

Replaces placeholder text while preserving formatting. Handles Word's run-splitting.

```bash
uv run --with python-docx python3 ${CLAUDE_PLUGIN_ROOT}/skills/docx/scripts/docx_tool.py edit "/path/to/file.docx" '{"{{NAME}}": "John Doe", "{{DATE}}": "2026-02-09"}' "/path/to/output.docx"
```

If output path omitted, overwrites the input file.

### Set Table Cell

```bash
uv run --with python-docx python3 ${CLAUDE_PLUGIN_ROOT}/skills/docx/scripts/docx_tool.py set-cell "/path/to/file.docx" 0 2 3 "New Value" "/path/to/output.docx"
```

Arguments: `<table_index> <row> <col> "value"`. Zero-indexed.

### Export to PDF

Uses `docx2pdf` which automates MS Word for perfect-quality conversion.

```bash
uvx docx2pdf "/path/to/file.docx" "/path/to/output.pdf"
```

If output path omitted, saves PDF next to the docx with `.pdf` extension.

## Workflow

For filling a form/template:

```
- [ ] Read document to identify fields and structure
- [ ] Prepare replacements JSON
- [ ] Copy original as backup: cp original.docx original.backup.docx
- [ ] Run edit with replacements
- [ ] Read output to verify changes
- [ ] Export to PDF if needed: uvx docx2pdf
```

## Best Practices

1. Always `read` first to understand document structure
2. Back up originals before editing
3. Use exact text from `read` output as replacement keys
4. Verify edits by reading the output file
