#!/usr/bin/env bash
# validate-md.sh — pre-flight checks for Markdown before PDF conversion
# Usage: validate-md.sh <file.md>
# Exit codes: 0 = pass (warnings only), 1 = errors found, 2 = usage error
set -euo pipefail

FILE="${1:-}"
[[ -z "$FILE" ]] && { echo "Usage: validate-md.sh <file.md>"; exit 2; }
[[ ! -f "$FILE" ]] && { echo "ERROR: File not found: $FILE"; exit 2; }

ERRORS=0
WARNINGS=0
DIR="$(dirname "$FILE")"

err()  { echo "❌ ERROR: $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "⚠️  WARN:  $1"; WARNINGS=$((WARNINGS + 1)); }
info() { echo "ℹ️  INFO:  $1"; }

# ── Strip code blocks for content checks ─────────────
# Used for: heading hierarchy, HTML tags, empty links, broken images, security
# Original $FILE used for: encoding, BOM, empty file, frontmatter, code fence counting, table validation
STRIPPED_FILE=$(mktemp)
trap 'rm -f "$STRIPPED_FILE"' EXIT
awk '
  /^\s*```/ || /^\s*~~~/ { in_code = !in_code; next }
  in_code { next }
  { print }
' "$FILE" | sed 's/`[^`]*`//g' > "$STRIPPED_FILE"

# ── Encoding ──────────────────────────────────────────
if file -b --mime-encoding "$FILE" | grep -qvi 'utf-8\|ascii\|us-ascii'; then
  DETECTED=$(file -b --mime-encoding "$FILE")
  err "File encoding is $DETECTED — expected UTF-8"
fi

# ── BOM check ─────────────────────────────────────────
if head -c3 "$FILE" | xxd -p | grep -q '^efbbbf'; then
  warn "File has UTF-8 BOM — may cause rendering issues"
fi

# ── Empty file ────────────────────────────────────────
CONTENT_LINES=$(grep -cve '^\s*$' "$FILE" 2>/dev/null || true)
CONTENT_LINES=${CONTENT_LINES:-0}
if [[ "$CONTENT_LINES" -eq 0 ]]; then
  err "File is empty or contains only whitespace"
fi

# ── Frontmatter YAML validation ──────────────────────
if head -1 "$FILE" | grep -q '^---'; then
  # Closing --- must appear within the first 50 lines (not just an HR later in file)
  FM_END=$(tail -n +2 "$FILE" | head -n 49 | grep -n '^---' | head -1 | cut -d: -f1)
  if [[ -z "$FM_END" ]]; then
    err "Frontmatter opened but never closed (missing closing --- within first 50 lines)"
  fi
fi

# ── Unclosed code blocks ─────────────────────────────
BACKTICK_FENCES=$(grep -c '^\s*```' "$FILE" 2>/dev/null || true)
BACKTICK_FENCES=${BACKTICK_FENCES:-0}
if [[ "$BACKTICK_FENCES" -gt 0 ]] && (( BACKTICK_FENCES % 2 != 0 )); then
  err "Odd number of \`\`\` fences ($BACKTICK_FENCES) — unclosed code block"
fi

TILDE_FENCES=$(grep -c '^\s*~~~' "$FILE" 2>/dev/null || true)
TILDE_FENCES=${TILDE_FENCES:-0}
if [[ "$TILDE_FENCES" -gt 0 ]] && (( TILDE_FENCES % 2 != 0 )); then
  err "Odd number of ~~~ fences ($TILDE_FENCES) — unclosed code block"
fi

# ── Heading hierarchy (on stripped file — no headings inside code blocks) ──
PREV_LEVEL=0
while IFS= read -r line; do
  HASHES="${line%%[^#]*}"
  LEVEL=${#HASHES}
  if (( PREV_LEVEL > 0 && LEVEL > PREV_LEVEL + 1 )); then
    warn "Heading skip: h${PREV_LEVEL} → h${LEVEL} ('${line:0:60}')"
  fi
  PREV_LEVEL=$LEVEL
done < <(grep -E '^#{1,6} ' "$STRIPPED_FILE" 2>/dev/null || true)

# ── Broken relative image links (on stripped file) ──
while IFS= read -r match; do
  IMG_PATH="${match#*](}"
  IMG_PATH="${IMG_PATH%)}"
  IMG_PATH="${IMG_PATH%%\"*}"
  IMG_PATH="${IMG_PATH%% *}"
  # skip URLs and data URIs
  [[ "$IMG_PATH" =~ ^https?:// || "$IMG_PATH" =~ ^data: ]] && continue
  FULL="$DIR/$IMG_PATH"
  if [[ ! -f "$FULL" ]]; then
    err "Broken image link: $IMG_PATH"
  fi
done < <(grep -oE '!\[[^]]*\]\([^)]+\)' "$STRIPPED_FILE" 2>/dev/null || true)

# ── Empty links (on stripped file) ───────────────────
if grep -qE '\[.*\]\(\s*\)' "$STRIPPED_FILE" 2>/dev/null; then
  warn "Empty link target found: [text]()"
fi

# ── Dangerous HTML tags (on stripped file) ───────────
for TAG in script iframe object embed form; do
  if grep -qiE "<${TAG}[ >]" "$STRIPPED_FILE" 2>/dev/null; then
    err "Dangerous HTML tag <${TAG}> may break PDF layout"
  fi
done

# ── Security checks (on stripped file) ───────────────
# Event handlers (onerror, onclick, onload etc.)
if grep -qiE '<[^>]+\bon[a-z]+\s*=' "$STRIPPED_FILE"; then
  err "HTML event handler detected (potential XSS)"
fi

# file:// protocol
if grep -qiE 'file://' "$STRIPPED_FILE"; then
  err "file:// URL detected — local file access risk"
fi

# <link> and <style> tags (external resource loading)
for TAG in link style; do
  if grep -qiE "<${TAG}[ >]" "$STRIPPED_FILE"; then
    warn "HTML <${TAG}> tag may load external resources"
  fi
done

# ── Table validation (on original file with IN_CODE tracking) ────────────────
IN_TABLE=0
TABLE_LINE=0
HEADER_COLS=0
TABLE_START=0
HAS_SEPARATOR=0

check_table_end() {
  if (( IN_TABLE && !HAS_SEPARATOR )); then
    err "Table at line $TABLE_START has no separator row (|---|)"
  fi
  IN_TABLE=0; HEADER_COLS=0; HAS_SEPARATOR=0
}

IN_CODE=0
LINENUM=0
while IFS= read -r line; do
  LINENUM=$((LINENUM + 1))

  # Skip lines inside code blocks (backtick or tilde fences)
  if echo "$line" | grep -qE '^\s*(```|~~~)'; then
    if (( IN_CODE )); then IN_CODE=0; else IN_CODE=1; fi
    continue
  fi
  (( IN_CODE )) && continue

  if echo "$line" | grep -qE '^\s*\|'; then
    if (( !IN_TABLE )); then
      IN_TABLE=1; TABLE_START=$LINENUM; TABLE_LINE=0; HAS_SEPARATOR=0
    fi
    TABLE_LINE=$((TABLE_LINE + 1))

    # Count columns: strip leading/trailing pipe, then split by |
    STRIPPED=$(echo "$line" | sed 's/^ *//;s/ *$//')
    # Перед подсчётом — убрать inline code (бэктики с содержимым)
    COL_LINE=$(echo "$STRIPPED" | sed 's/`[^`]*`//g')
    COLS=$(echo "$COL_LINE" | sed 's/^[[:space:]]*|//; s/|[[:space:]]*$//' | awk -F'|' '{print NF}')

    # Separator row — support both leading-pipe and non-leading-pipe tables
    if echo "$line" | grep -qE '^\s*\|(\s*:?-+:?\s*\|)+\s*$|^\s*:?-+:?\s*(\|\s*:?-+:?\s*)+$'; then
      HAS_SEPARATOR=1
      continue
    fi

    # Header row (first row)
    if (( TABLE_LINE == 1 )); then
      HEADER_COLS=$COLS
      # Check empty header cells (use COL_LINE with inline code stripped)
      if echo "$COL_LINE" | grep -qE '\|\s*\|'; then
        warn "Table at line $TABLE_START: empty header cell detected"
      fi
    else
      # Column count consistency
      if (( HEADER_COLS > 0 && COLS != HEADER_COLS )); then
        err "Table at line $TABLE_START: row $LINENUM has $COLS columns, expected $HEADER_COLS"
      fi
    fi

    # Long cell content (>120 chars) — use COL_LINE with inline code stripped
    while IFS='|' read -ra CELLS; do
      for CELL in "${CELLS[@]}"; do
        TRIMMED=$(echo "$CELL" | sed 's/^ *//;s/ *$//')
        if (( ${#TRIMMED} > 120 )); then
          warn "Table at line $TABLE_START: cell >120 chars at line $LINENUM (may overflow in PDF)"
          break 2
        fi
      done
    done <<< "$COL_LINE"

  else
    (( IN_TABLE )) && check_table_end
  fi
done < "$FILE"
(( IN_TABLE )) && check_table_end

# ── Mermaid blocks ───────────────────────────────────
MERMAID_COUNT=$(grep -cE '^\s*(```|~~~)mermaid' "$FILE" 2>/dev/null || true)
MERMAID_COUNT=${MERMAID_COUNT:-0}
if (( MERMAID_COUNT > 0 )); then
  if command -v mmdc &>/dev/null; then
    info "Found $MERMAID_COUNT Mermaid diagram(s) — will be pre-rendered via mmdc + inline-svg.py (see Step 2)"
  else
    warn "Found $MERMAID_COUNT Mermaid diagram(s) — mmdc not installed, diagrams will render as raw text"
    info "Install: npm i -g @mermaid-js/mermaid-cli"
  fi
fi

# ── Very long code lines ────────────────────────────
IN_CODE_BLOCK=0
while IFS= read -r line; do
  if echo "$line" | grep -qE '^\s*```'; then
    [[ "$IN_CODE_BLOCK" -eq 1 ]] && IN_CODE_BLOCK=0 || IN_CODE_BLOCK=1
    continue
  fi
  if [[ "$IN_CODE_BLOCK" -eq 1 ]] && [[ "${#line}" -gt 120 ]]; then
    warn "Code line >120 chars — may overflow in PDF: '${line:0:40}...'"
    break  # report once
  fi
done < "$FILE"

# ── Large file warning ───────────────────────────────
FILE_SIZE=$(wc -c < "$FILE" | tr -d ' ')
if (( FILE_SIZE > 1048576 )); then
  warn "File is $(( FILE_SIZE / 1024 ))KB — large files may be slow to convert"
fi

# ── Summary ──────────────────────────────────────────
echo ""
echo "━━━ Validation Summary ━━━"
echo "File:     $FILE"
echo "Errors:   $ERRORS"
echo "Warnings: $WARNINGS"

if (( ERRORS > 0 )); then
  echo "Status:   FAIL — fix errors before conversion"
  exit 1
else
  if (( WARNINGS > 0 )); then
    echo "Status:   PASS with warnings"
  else
    echo "Status:   PASS ✅"
  fi
  exit 0
fi
