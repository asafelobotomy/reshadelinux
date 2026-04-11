#!/usr/bin/env bash
# purpose:  Auto-format files after agent edits them
# when:     PostToolUse hook — fires after a tool completes successfully
# inputs:   JSON via stdin with tool_name and tool_input
# outputs:  JSON with additionalContext if lint errors found
# risk:     safe
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/') || TOOL_NAME=""

# Only run after file-editing tools
if [[ "$TOOL_NAME" != *"edit"* && "$TOOL_NAME" != *"create"* && "$TOOL_NAME" != *"write"* && "$TOOL_NAME" != *"replace"* ]]; then
  echo '{"continue": true}'
  exit 0
fi

# Extract file paths from tool input
FILES=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    ti = data.get('tool_input', {})
    # Try common field names for file paths
    for key in ('filePath', 'file', 'path', 'files', 'file_path'):
        val = ti.get(key, '')
        if isinstance(val, list):
            for v in val:
                print(v)
        elif val:
            print(val)
except Exception:
    pass
" 2>/dev/null || echo "")

if [[ -z "$FILES" ]]; then
  echo '{"continue": true}'
  exit 0
fi

# Resolve workspace root for boundary checks
WORKSPACE_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

while IFS= read -r filepath; do
  [[ -z "$filepath" ]] && continue
  [[ ! -f "$filepath" ]] && continue

  # Workspace boundary check — reject paths outside the repo root
  real_path=$(realpath "$filepath" 2>/dev/null) || continue
  case "$real_path" in
    "$WORKSPACE_ROOT"/*)  ;;
    *) continue ;;
  esac

  EXT="${filepath##*.}"
  case "$EXT" in
    js|jsx|ts|tsx|mjs|cjs)
      if command -v npx &>/dev/null && [[ -f node_modules/.bin/prettier ]]; then
        npx prettier --write "$filepath" 2>/dev/null || true
      fi
      ;;
    py)
      if command -v black &>/dev/null; then
        black --quiet "$filepath" 2>/dev/null || true
      elif command -v ruff &>/dev/null; then
        ruff format "$filepath" 2>/dev/null || true
      fi
      ;;
    rs)
      if command -v rustfmt &>/dev/null; then
        rustfmt "$filepath" 2>/dev/null || true
      fi
      ;;
    go)
      if command -v gofmt &>/dev/null; then
        gofmt -w "$filepath" 2>/dev/null || true
      fi
      ;;
  esac
done <<< "$FILES"

echo '{"continue": true}'
