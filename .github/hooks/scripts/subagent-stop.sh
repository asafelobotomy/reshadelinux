#!/usr/bin/env bash
# purpose:  Log subagent completion and write diary entry if durable findings exist
# when:     SubagentStop hook — fires after a subagent finishes
# inputs:   JSON via stdin with subagent result details
# outputs:  JSON with additionalContext summarising outcome
# risk:     safe — creates/appends diary files only
# ESCALATION: none
set -euo pipefail

# shellcheck source=.github/hooks/scripts/lib-hooks.sh
source "$(dirname "$0")/lib-hooks.sh"

INPUT=$(cat)

# Extract subagent name and result summary
AGENT_NAME=$(printf '%s' "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('agentName','unknown'))" 2>/dev/null) || AGENT_NAME="unknown"
[[ -z "$AGENT_NAME" ]] && AGENT_NAME="unknown"

RESULT=$(printf '%s' "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result','')[:200])" 2>/dev/null) || RESULT=""

# Write diary entry if there is a result worth recording
AGENT_LOWER=$(printf '%s' "$AGENT_NAME" | tr '[:upper:]' '[:lower:]')
DIARY_DIR=".copilot/workspace/knowledge/diaries"
DIARY_FILE="${DIARY_DIR}/${AGENT_LOWER}.md"

if [[ -n "$RESULT" ]]; then
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  ENTRY="- ${TIMESTAMP} ${RESULT}"

  # Grep-before-write: skip if this finding already exists
  if [[ ! -f "$DIARY_FILE" ]] || ! grep -qF "$RESULT" "$DIARY_FILE" 2>/dev/null; then
    mkdir -p "$DIARY_DIR"
    # Create header if file is new
    if [[ ! -f "$DIARY_FILE" ]]; then
      printf '# %s Diary\n\n' "$AGENT_NAME" > "$DIARY_FILE"
    fi
    printf '%s\n' "$ENTRY" >> "$DIARY_FILE"

    # Enforce 30-line cap (keep header + last 28 entries)
    if [[ -f "$DIARY_FILE" ]]; then
      LINE_COUNT=$(wc -l < "$DIARY_FILE")
      if (( LINE_COUNT > 30 )); then
        # Keep first 2 lines (header + blank) and last 28 entries
        { head -2 "$DIARY_FILE"; tail -28 "$DIARY_FILE"; } > "${DIARY_FILE}.tmp"
        mv "${DIARY_FILE}.tmp" "$DIARY_FILE"
      fi
    fi
  fi
fi

# Build summary context
CONTEXT="Subagent ${AGENT_NAME} completed. Review results before continuing."

# JSON-escape the context
CONTEXT_ESC=$(json_escape "$CONTEXT")

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": "${CONTEXT_ESC}"
  }
}
EOF
