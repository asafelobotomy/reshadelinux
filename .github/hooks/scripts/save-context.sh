#!/usr/bin/env bash
# purpose:  Save critical workspace context before conversation compaction
# when:     PreCompact hook — fires when context is about to be truncated
# inputs:   JSON via stdin with trigger field
# outputs:  JSON with additionalContext summarising saved state
# risk:     safe
# ESCALATION: none
set -euo pipefail

# shellcheck source=.github/hooks/scripts/lib-hooks.sh
source "$(dirname "$0")/lib-hooks.sh"

INPUT_JSON=$(cat 2>/dev/null || echo "")

clock_summary() {
  local script_dir
  command -v python3 >/dev/null 2>&1 || return 0
  [[ -f .copilot/workspace/runtime/state.json || -f .copilot/workspace/runtime/.heartbeat-events.jsonl ]] || return 0

  script_dir="$(cd "$(dirname "$0")" && pwd)"
  python3 "$script_dir/heartbeat_clock_summary.py" 2>/dev/null || true
}

extract_trigger() {
  local input_json="${1:-}"

  [[ -n "$input_json" ]] || return 0

  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$input_json" | python3 -c "
import json, sys
try:
    payload = json.load(sys.stdin)
    trigger = payload.get('trigger', '')
    print(trigger if isinstance(trigger, str) else '', end='')
except Exception:
    print('', end='')
" 2>/dev/null || true
    return 0
  fi

  echo "$input_json" \
    | grep -o '"trigger"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -1 \
    | sed 's/.*: *"\(.*\)"/\1/'
}

extract_memory_summary() {
  local memory_file=".copilot/workspace/knowledge/MEMORY.md"

  [[ -f "$memory_file" ]] || return 0

  if command -v python3 >/dev/null 2>&1; then
  python3 - "$memory_file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
entries = []
current_section = ""
i = 0

def _row_priority(cells, header_cells):
    """Return 0 (highest) to 9 (lowest) based on Priority/Impact columns."""
    for idx, h in enumerate(header_cells):
        hl = h.lower()
        if hl in ("priority", "impact") and idx < len(cells):
            val = cells[idx].lower().strip()
            if val in ("p1", "critical", "high"):
                return 0
            if val in ("p2", "notable", "medium"):
                return 1
            if val in ("p3", "informational", "low"):
                return 2
    return 5  # no priority column or unrecognised value

while i < len(lines):
  stripped = lines[i].strip()
  if stripped.startswith("## "):
    current_section = stripped[3:].strip()
    i += 1
    continue

  if current_section and stripped.startswith("|"):
    block = []
    while i < len(lines) and lines[i].lstrip().startswith("|"):
      block.append(lines[i].strip())
      i += 1

    if len(block) >= 3:
      header_cells = [cell.strip() for cell in block[0].strip("|").split("|")]
      scored_rows = []
      for row in block[2:]:
        cells = [cell.strip() for cell in row.strip("|").split("|")]
        meaningful = [cell for cell in cells if cell and cell != "*(to be discovered)*"]
        if meaningful:
          pri = _row_priority(cells, header_cells)
          scored_rows.append((pri, cells))

      if scored_rows:
        scored_rows.sort(key=lambda x: x[0])
        best = scored_rows[0][1]
        preview = " | ".join(cell for cell in best if cell)
        entries.append(f"{current_section}: {preview}")

    continue

  i += 1

if not entries:
  fallback = []
  for line in lines:
    stripped = line.strip()
    if not stripped:
      continue
    if stripped.startswith(("#", "|", "<!--", "*(")):
      continue
    if set(stripped) <= {"-", "|", " "}:
      continue
    if stripped.startswith("- "):
      stripped = stripped[2:].strip()
    if ":" not in stripped and not line.lstrip().startswith("- "):
      continue
    fallback.append(stripped)
  entries = fallback[-3:]

summary = " || ".join(entries[:3])
print(summary[:500], end="")
PY
    return 0
  fi

  tail -5 "$memory_file" 2>/dev/null | tr '\n' ' ' | head -c 500 || echo ""
}

extract_soul_summary() {
  local soul_file=".copilot/workspace/identity/SOUL.md"

  [[ -f "$soul_file" ]] || return 0

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$soul_file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
entries = [line.strip()[2:].strip() for line in lines if line.strip().startswith("- ")]

if not entries:
    fallback = []
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith(("#", "*(", "<!--")):
            continue
        fallback.append(stripped)
    entries = fallback[:3]

summary = " || ".join(entries[:5])
print(summary[:400], end="")
PY
    return 0
  fi

grep -v '^[[:space:]]*#' "$soul_file" 2>/dev/null | grep -v '^[[:space:]]*$' | head -5 | tr '\n' ' ' | head -c 400 || echo ""
}

append_summary_line() {
  local label="$1" value="$2"

  [[ -n "$value" ]] || return 0
  SUMMARY_LINES+=("- ${label}: ${value}")
}

SUMMARY_LINES=()

TRIGGER=$(extract_trigger "$INPUT_JSON")
append_summary_line "Trigger" "$TRIGGER"

# Heartbeat pulse
if [[ -f .copilot/workspace/operations/HEARTBEAT.md ]]; then
  PULSE=$(grep -m1 'HEARTBEAT' .copilot/workspace/operations/HEARTBEAT.md 2>/dev/null || echo "unknown")
  append_summary_line "Heartbeat" "$PULSE"
fi

CLOCK_SUMMARY=$(clock_summary 2>/dev/null || echo "")
append_summary_line "Clock" "$CLOCK_SUMMARY"

MEMORY_SUMMARY=$(extract_memory_summary 2>/dev/null || echo "")
append_summary_line "Memory entries" "$MEMORY_SUMMARY"

SOUL_SUMMARY=$(extract_soul_summary 2>/dev/null || echo "")
append_summary_line "SOUL cues" "$SOUL_SUMMARY"

# Git status snapshot
GIT_STATUS=$(git status --porcelain 2>/dev/null | head -10 || echo "")
if [[ -n "$GIT_STATUS" ]]; then
  MODIFIED_COUNT=$(echo "$GIT_STATUS" | wc -l | tr -d ' ')
  append_summary_line "Git" "${MODIFIED_COUNT} modified files"
fi

if [[ ${#SUMMARY_LINES[@]} -eq 0 ]]; then
  echo '{"continue": true}'
  exit 0
fi

SUMMARY=$(printf 'Pre-compaction workspace snapshot:\n%s\n' "${SUMMARY_LINES[@]}")
SUMMARY=$(printf '%s' "$SUMMARY" | head -c 2000)

SUMMARY_ESCAPED=$(json_escape "$SUMMARY")

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": "${SUMMARY_ESCAPED}"
  }
}
EOF
