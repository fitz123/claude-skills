#!/usr/bin/env python3
"""DOCX read/edit tool for Claude Code. Run via: uv run --with python-docx python3 this_script.py"""

import json
import sys
from docx import Document
from docx.oxml.ns import qn


def replace_across_runs(paragraph, old_text, new_text):
    """Replace text that may span multiple runs, preserving formatting."""
    full_text = ""
    char_to_run = []
    for run_idx, run in enumerate(paragraph.runs):
        for char_idx in range(len(run.text)):
            char_to_run.append((run_idx, char_idx))
        full_text += run.text

    if old_text not in full_text:
        return False

    start = full_text.index(old_text)
    end = start + len(old_text)

    first_run_idx, first_char = char_to_run[start]
    last_run_idx, last_char = char_to_run[end - 1]
    runs = paragraph.runs

    prefix = runs[first_run_idx].text[:first_char]
    suffix = runs[last_run_idx].text[last_char + 1:]

    if first_run_idx == last_run_idx:
        runs[first_run_idx].text = prefix + new_text + suffix
    else:
        runs[first_run_idx].text = prefix + new_text
        for i in range(first_run_idx + 1, last_run_idx):
            runs[i].text = ""
        runs[last_run_idx].text = suffix
    return True


def read_docx(filepath):
    doc = Document(filepath)

    print("=" * 60)
    print(f"DOCUMENT: {filepath}")
    print("=" * 60)

    # Paragraphs
    print("\n--- PARAGRAPHS ---")
    for i, para in enumerate(doc.paragraphs):
        if para.text.strip():
            style = para.style.name if para.style else "Normal"
            print(f"[{i}] ({style}) {para.text}")

    # Tables
    for t_idx, table in enumerate(doc.tables):
        print(f"\n--- TABLE {t_idx} ({len(table.rows)} rows x {len(table.columns)} cols) ---")
        for r_idx, row in enumerate(table.rows):
            cells = [cell.text.strip().replace("\n", " | ") for cell in row.cells]
            print(f"  [{r_idx}] {' │ '.join(cells)}")

    # Content controls (form fields)
    nsmap = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    sdts = doc.element.body.findall(".//w:sdt", nsmap)
    if sdts:
        print("\n--- CONTENT CONTROLS ---")
        for sdt in sdts:
            sdt_pr = sdt.find("w:sdtPr", nsmap)
            tag = sdt_pr.find("w:tag", nsmap) if sdt_pr is not None else None
            alias = sdt_pr.find("w:alias", nsmap) if sdt_pr is not None else None
            content = sdt.find("w:sdtContent", nsmap)
            texts = content.findall(".//w:t", nsmap) if content is not None else []
            tag_val = tag.get(qn("w:val")) if tag is not None else None
            alias_val = alias.get(qn("w:val")) if alias is not None else None
            text_val = "".join(t.text or "" for t in texts)
            label = alias_val or tag_val or "(unnamed)"
            print(f"  {label}: {text_val!r}")

    # Headers and footers
    for s_idx, section in enumerate(doc.sections):
        for name, hf in [("Header", section.header), ("Footer", section.footer)]:
            if hf.is_linked_to_previous:
                continue
            texts = [p.text for p in hf.paragraphs if p.text.strip()]
            if texts:
                print(f"\n--- {name.upper()} (section {s_idx}) ---")
                for t in texts:
                    print(f"  {t}")


def edit_docx(filepath, replacements_json, output_path=None):
    replacements = json.loads(replacements_json)
    doc = Document(filepath)
    output_path = output_path or filepath
    count = 0

    def process_paragraphs(paragraphs):
        nonlocal count
        for para in paragraphs:
            for old, new in replacements.items():
                while old in para.text:
                    if replace_across_runs(para, old, new):
                        count += 1
                    else:
                        break

    # Paragraphs
    process_paragraphs(doc.paragraphs)

    # Tables
    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                process_paragraphs(cell.paragraphs)

    # Headers/footers
    for section in doc.sections:
        for hf in [section.header, section.footer]:
            if not hf.is_linked_to_previous:
                process_paragraphs(hf.paragraphs)

    doc.save(output_path)
    print(f"Replaced {count} occurrence(s). Saved to: {output_path}")


def set_cell(filepath, table_idx, row, col, value, output_path=None):
    doc = Document(filepath)
    output_path = output_path or filepath
    table_idx, row, col = int(table_idx), int(row), int(col)

    if table_idx >= len(doc.tables):
        print(f"Error: table index {table_idx} out of range (have {len(doc.tables)} tables)")
        sys.exit(1)

    cell = doc.tables[table_idx].cell(row, col)
    if cell.paragraphs and cell.paragraphs[0].runs:
        cell.paragraphs[0].runs[0].text = value
        for run in cell.paragraphs[0].runs[1:]:
            run.text = ""
    else:
        cell.text = value

    doc.save(output_path)
    print(f"Set table[{table_idx}][{row}][{col}] = {value!r}. Saved to: {output_path}")


def main():
    if len(sys.argv) < 3:
        print("Usage:")
        print("  docx_tool.py read <file>")
        print('  docx_tool.py edit <file> \'{"old":"new"}\' [output]')
        print("  docx_tool.py set-cell <file> <table> <row> <col> \"value\" [output]")
        sys.exit(1)

    cmd = sys.argv[1]
    filepath = sys.argv[2]

    if cmd == "read":
        read_docx(filepath)
    elif cmd == "edit":
        replacements_json = sys.argv[3]
        output_path = sys.argv[4] if len(sys.argv) > 4 else None
        edit_docx(filepath, replacements_json, output_path)
    elif cmd == "set-cell":
        table_idx, row, col = sys.argv[3], sys.argv[4], sys.argv[5]
        value = sys.argv[6]
        output_path = sys.argv[7] if len(sys.argv) > 7 else None
        set_cell(filepath, table_idx, row, col, value, output_path)
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)


if __name__ == "__main__":
    main()
