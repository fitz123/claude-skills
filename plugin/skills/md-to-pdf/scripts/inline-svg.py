#!/usr/bin/env python3
"""Inline SVG files referenced as images in markdown.

Usage: inline-svg.py <input.md> [output.md]
If output is omitted, prints to stdout.

Replaces ![alt](./path.svg) and ![alt](path.svg) with raw <svg> content wrapped in a <div>.
Non-SVG images are left untouched.
"""
import re
import sys
from pathlib import Path

SVG_IMAGE_RE = re.compile(r"!\[[^\]]*\]\((?P<path>(?:\./)?[^)\s]+\.svg)\)")


def inline_svgs(md_path: Path) -> str:
    content = md_path.read_text(encoding="utf-8")
    base = md_path.parent

    def replacer(m: re.Match) -> str:
        rel = m.group("path").lstrip("./")
        svg_path = base / rel
        if not svg_path.exists():
            return m.group(0)
        svg = svg_path.read_text(encoding="utf-8")
        # Strip XML declaration if present
        svg = re.sub(r"<\?xml[^?]*\?>\s*", "", svg)
        return f'<div class="mermaid-diagram">\n{svg}\n</div>'

    return SVG_IMAGE_RE.sub(replacer, content)


def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.md> [output.md]", file=sys.stderr)
        sys.exit(1)

    result = inline_svgs(Path(sys.argv[1]))

    if len(sys.argv) >= 3:
        Path(sys.argv[2]).write_text(result, encoding="utf-8")
    else:
        print(result)


if __name__ == "__main__":
    main()
