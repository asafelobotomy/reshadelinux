#!/usr/bin/env bash
# purpose:  Orchestrate heartbeat trigger state and retrospective gating.
# when:     Invoked by lifecycle hooks (SessionStart/PostToolUse/PreCompact/Stop/UserPromptSubmit).
# inputs:   JSON on stdin + --trigger <session_start|pre_tool|soft_post_tool|compaction|stop|user_prompt|explicit>.
# outputs:  JSON hook response (`continue` or Stop `decision:block`).
# risk:     safe
# source:   original
# ESCALATION: none
# STOP LOOP: if stop_hook_active is true in the Stop payload, do not re-enter blocking Stop logic.
set -euo pipefail

TRIGGER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trigger)
      TRIGGER="${2:-}"
      shift 2
      ;;
    *)
      echo '{"continue": true}'
      exit 0
      ;;
  esac
done

if [[ -z "$TRIGGER" ]]; then
  echo '{"continue": true}'
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT=$(cat)

TRIGGER="$TRIGGER" HOOK_INPUT="$INPUT" python3 "$SCRIPT_DIR/pulse_runtime.py"