#!/usr/bin/env python3
"""Sort Claude Code permission entries in settings JSON files.

Groups by type (Bash, Read, Skill, WebFetch, WebSearch, mcp__), then sorts
alphabetically within each group. Preserves all other keys in the JSON.

Usage:
  sort-permissions.py <file> [<file>...]
  sort-permissions.py --all          # Sort all known settings files
"""

import json
import sys
from pathlib import Path

KNOWN_FILES = [
    Path.home() / ".claude" / "settings.local.json",
    Path.home() / "ordercapital" / "ai" / "settings.work.json",
]

GROUP_ORDER = ["Bash", "Read", "Skill", "WebFetch", "WebSearch", "mcp__"]


def group_key(entry):
    for i, prefix in enumerate(GROUP_ORDER):
        if entry.startswith(prefix):
            return (i, entry.lower())
    return (len(GROUP_ORDER), entry.lower())


def sort_permissions(filepath):
    filepath = Path(filepath)
    if not filepath.exists():
        print(f"skip: {filepath} (not found)")
        return False

    with open(filepath) as f:
        data = json.load(f)

    perms = data.get("permissions")
    if not perms:
        print(f"skip: {filepath} (no permissions key)")
        return False

    changed = False
    for key in ("allow", "deny"):
        entries = perms.get(key, [])
        if not entries:
            continue
        sorted_entries = sorted(entries, key=group_key)
        if sorted_entries != entries:
            perms[key] = sorted_entries
            changed = True

    if changed:
        with open(filepath, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        print(f"sorted: {filepath}")
    else:
        print(f"ok: {filepath} (already sorted)")
    return changed


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip())
        sys.exit(1)

    if sys.argv[1] == "--all":
        files = KNOWN_FILES
    else:
        files = sys.argv[1:]

    for f in files:
        sort_permissions(f)


if __name__ == "__main__":
    main()
