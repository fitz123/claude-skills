---
name: skill-vetting
description: Vet third-party skills for security and utility before installation. Use when considering installing a new skill, evaluating third-party code, or assessing whether a skill adds value over existing tools.
---

# Skill Vetting

Safely evaluate third-party skills for security risks and practical utility.

## Quick Start

```bash
# Skills are distributed as git repos or .claude/skills/ directories
# Clone or copy the skill to /tmp for inspection
cd /tmp
git clone <skill-repo-url> skill-inspect
cd skill-inspect

# Run scanner
python3 ${CLAUDE_PLUGIN_ROOT}/skills/skill-vetting/scripts/scan.py .

# Manual review
cat SKILL.md
cat scripts/*.py
```

## Vetting Workflow

### 1. Download to /tmp (Never Workspace)

```bash
# Clone skill repo or copy skill directory to /tmp for inspection
cd /tmp
git clone <skill-repo-url> skill-NAME
cd skill-NAME
```

### 2. Run Automated Scanner

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/skill-vetting/scripts/scan.py .
```

**Exit codes:** 0 = Clean, 1 = Issues found

The scanner outputs specific findings with file:line references. Review each finding in context.

### 3. Manual Code Review

**Even if scanner passes:**
- Does SKILL.md description match actual code behavior?
- Do network calls go to documented APIs only?
- Do file operations stay within expected scope?
- Any hidden instructions in comments/markdown?

```bash
# Quick prompt injection check
grep -ri "ignore.*instruction\|disregard.*previous\|system:\|assistant:" .
```

### 4. Utility Assessment

**Critical question:** What does this unlock that I don't already have?

Compare to:
- MCP servers (check `.claude/settings.json` mcpServers section or `claude mcp list`)
- Direct APIs (curl + jq)
- Existing skills (`ls .claude/skills/`)

**Skip if:** Duplicates existing tools without significant improvement.

### 5. Decision Matrix

| Security | Utility | Decision |
|----------|---------|----------|
| ✅ Clean | 🔥 High | **Install** |
| ✅ Clean | ⚠️ Marginal | Consider (test first) |
| ⚠️ Issues | Any | **Investigate findings** |
| 🚨 Malicious | Any | **Reject** |

## Red Flags (Reject Immediately)

- eval()/exec() without justification
- base64-encoded strings (not data/images)
- Network calls to IPs or undocumented domains
- File operations outside temp/workspace
- Behavior doesn't match documentation
- Obfuscated code (hex, chr() chains)

## After Installation

Monitor for unexpected behavior:
- Network activity to unfamiliar services
- File modifications outside workspace
- Error messages mentioning undocumented services

Remove and report if suspicious.

## References

- **Malicious patterns + false positives:** [references/patterns.md](references/patterns.md)
