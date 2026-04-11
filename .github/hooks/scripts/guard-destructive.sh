#!/usr/bin/env bash
# purpose:  Block dangerous terminal commands before execution
# when:     PreToolUse hook — fires before the agent invokes any tool
# inputs:   JSON via stdin with tool_name and tool_input
# outputs:  JSON with permissionDecision (allow/deny/ask)
# risk:     safe
# ESCALATION: ask
#
# This hook is complementary to VS Code's built-in terminal auto-approval
# (github.copilot.chat.agent.terminal.allowList / denyList). This hook runs
# at the PreToolUse level (before command dispatch); auto-approval runs at
# the terminal level (after dispatch, before execution). Use both for
# defense-in-depth.
set -euo pipefail

# shellcheck source=.github/hooks/scripts/lib-hooks.sh
source "$(dirname "$0")/lib-hooks.sh"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/') || TOOL_NAME=""

# Only guard terminal/command tools
if [[ "$TOOL_NAME" != *"terminal"* && "$TOOL_NAME" != *"command"* && "$TOOL_NAME" != *"bash"* && "$TOOL_NAME" != *"shell"* ]]; then
  echo '{"continue": true}'
  exit 0
fi

# python3 is required to parse tool_input JSON reliably.
# Without it, TOOL_INPUT would be empty and all patterns would pass unchecked.
if ! command -v python3 >/dev/null 2>&1; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "python3 not found — guard-destructive hook cannot parse command. Falling back to manual confirmation."
  }
}
EOF
  exit 0
fi

TOOL_INPUT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    ti = data.get('tool_input', {})
    command = ti.get('command', '')
    print(command if isinstance(command, str) else '')
except Exception:
    print('')
" 2>/dev/null || echo "")

if [[ -z "$TOOL_INPUT" ]]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "tool_input.command is required for terminal tools. Falling back to manual confirmation."
  }
}
EOF
  exit 0
fi

AGENT_NAME=$(echo "$INPUT" | python3 -c "
import sys, json
try:
  data = json.load(sys.stdin)
  candidates = [
    data.get('agent_name'),
    data.get('agentName'),
    (data.get('context') or {}).get('agentName'),
    (data.get('context') or {}).get('agent_name'),
    (data.get('session') or {}).get('agentName'),
    (data.get('session') or {}).get('agent_name'),
  ]
  for value in candidates:
    if isinstance(value, str) and value.strip():
      print(value.strip())
      break
  else:
    print('')
except Exception:
  print('')
" 2>/dev/null || echo "")

# Blocked patterns — dangerous commands that should never auto-execute
BLOCKED_PATTERNS=(
  'rm -rf /([^a-zA-Z0-9._-]|$)'
  'rm -rf ~([^a-zA-Z0-9._/-]|$)'
  'rm -rf \.([[:space:]]|$)'
  'DROP TABLE'
  'DROP DATABASE'
  'TRUNCATE TABLE'
  'DELETE FROM .* WHERE 1'
  'mkfs\.'
  'dd if=.* of=/dev/'
  ':\(\)\{:[|]:&\};:'
  'chmod -R 777 /([^a-zA-Z0-9._-]|$)'
  'curl .*[|].*sh'
  'wget .*[|].*sh'
)

# Allow pure read-only pattern searches so investigations can inspect the guard
# definitions without tripping on the blocked regex literals themselves.
is_readonly_pattern_search() {
  local command_text="$1"
  local lowered_command="$1"

  lowered_command=${lowered_command,,}

  if [[ ! "$command_text" =~ ^[[:space:]]*(rg|grep|findstr)($|[[:space:]]) && ! "$command_text" =~ ^[[:space:]]*git[[:space:]]+grep($|[[:space:]]) ]]; then
    return 1
  fi

  if [[ "$command_text" == *'&&'* || "$command_text" == *'||'* || "$command_text" == *';'* || "$command_text" == *'$('* || "$command_text" == *'`'* || "$command_text" == *'<'* || "$command_text" == *'>'* || "$command_text" == *' | '* ]]; then
    return 1
  fi

  local pattern
  for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if [[ "$lowered_command" == *"${pattern,,}"* ]]; then
      return 0
    fi
  done

  return 1
}

if is_readonly_pattern_search "$TOOL_INPUT"; then
  echo '{"continue": true}'
  exit 0
fi

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$TOOL_INPUT" | grep -qiE "$pattern"; then
    PATTERN_ESC=$(json_escape "$pattern")
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked by security hook: matched destructive pattern '${PATTERN_ESC}'"
  }
}
EOF
    exit 0
  fi
done

# Caution patterns — require user confirmation
CAUTION_PATTERNS=(
  'rm -rf'
  'rm -r '
  'chmod -R 777'
  'DROP '
  'DELETE FROM'
  'git push.*--force'
  'git reset --hard'
  'git clean -fd'
  'npm publish'
  'cargo publish'
  'pip install --'
)

for pattern in "${CAUTION_PATTERNS[@]}"; do
  if echo "$TOOL_INPUT" | grep -qiE "$pattern"; then
    PATTERN_ESC=$(json_escape "$pattern")
    COMMAND_ESC=$(json_escape "$(echo "$TOOL_INPUT" | head -c 200)")
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "Potentially destructive command detected: matches '${PATTERN_ESC}'. Requires user confirmation.",
    "additionalContext": "The command '${COMMAND_ESC}' matched a caution pattern. Verify this is intended before proceeding."
  }
}
EOF
    exit 0
  fi
done

# Read-only agent guardrails — Audit, Review, and Explore should not perform
# mutating terminal operations without explicit user approval.
if [[ "$AGENT_NAME" =~ ^(Audit|Review|Explore)$ ]]; then
  READONLY_WRITE_PATTERNS=(
    '(^|[;&|][[:space:]]*)(mkdir|touch|cp|mv|truncate|install)[[:space:]]'
    '(^|[;&|][[:space:]]*)(sed[[:space:]]+-i|perl[[:space:]]+-i|tee[[:space:]])'
    '(^|[;&|][[:space:]]*)(echo|printf).*>+'
    '(^|[;&|][[:space:]]*)(git[[:space:]]+(add|commit|push|reset|checkout|switch|merge|rebase|cherry-pick|revert|tag|stash))'
    '(^|[;&|][[:space:]]*)((npm|pnpm|yarn|bun)[[:space:]]+(install|add|remove|update|upgrade|publish))'
    '(^|[;&|][[:space:]]*)(pip|uv[[:space:]]+pip)[[:space:]]+install'
  )

  for pattern in "${READONLY_WRITE_PATTERNS[@]}"; do
    if echo "$TOOL_INPUT" | grep -qiE "$pattern"; then
      AGENT_ESC=$(json_escape "$AGENT_NAME")
      COMMAND_ESC=$(json_escape "$(echo "$TOOL_INPUT" | head -c 200)")
      cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "${AGENT_ESC} is a read-only agent. Mutating terminal commands require explicit user confirmation.",
    "additionalContext": "The command '${COMMAND_ESC}' appears to mutate files or repository state. Use the Code agent for implementation tasks or confirm this one-off command."
  }
}
EOF
      exit 0
    fi
  done
fi

# Safe — allow execution
echo '{"continue": true}'
