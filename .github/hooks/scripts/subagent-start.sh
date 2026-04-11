#!/usr/bin/env bash
# purpose:  Inject subagent governance context and diary summary when a subagent is spawned
# when:     SubagentStart hook — fires before a subagent begins work
# inputs:   JSON via stdin with subagent details
# outputs:  JSON with additionalContext including governance + diary summary
# risk:     safe
# ESCALATION: none
set -euo pipefail

# shellcheck source=.github/hooks/scripts/lib-hooks.sh
source "$(dirname "$0")/lib-hooks.sh"

INPUT=$(cat)

# Extract subagent name if available (python3 for robust JSON parsing)
AGENT_NAME=$(printf '%s' "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('agentName','unknown'))" 2>/dev/null) || AGENT_NAME="unknown"
[[ -z "$AGENT_NAME" ]] && AGENT_NAME="unknown"

# Build governance context
CONTEXT="Subagent governance: max depth 3. Inherited protocols: PDCA cycle, Tool Protocol, Skill Protocol. Agent: ${AGENT_NAME}."

# Inject diary summary if a diary file exists for this agent
AGENT_LOWER=$(printf '%s' "$AGENT_NAME" | tr '[:upper:]' '[:lower:]')
DIARY_FILE=".copilot/workspace/knowledge/diaries/${AGENT_LOWER}.md"
if [[ -f "$DIARY_FILE" ]]; then
  # Read the last 5 non-empty lines as a summary
  DIARY_TAIL=$(grep -v '^\s*$' "$DIARY_FILE" | tail -5 2>/dev/null || true)
  if [[ -n "$DIARY_TAIL" ]]; then
    CONTEXT="${CONTEXT} Recent diary entries: ${DIARY_TAIL}"
  fi
fi

# JSON-escape the context
CONTEXT_ESC=$(json_escape "$CONTEXT")

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": "${CONTEXT_ESC}"
  }
}
EOF
