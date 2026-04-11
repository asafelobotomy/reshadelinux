#!/usr/bin/env bash
set -euo pipefail
# lib-hooks.sh — shared utilities for agent lifecycle hook scripts.
# Source this file at the top of each hook script:
#   source "$(dirname "$0")/lib-hooks.sh"
# Do NOT execute this file directly.

# json_escape <string>
#   Return the string with JSON special characters escaped, suitable for
#   embedding inside a double-quoted JSON value.  Falls back to the raw
#   string if python3 is unavailable so hooks never crash on a missing dep.
json_escape() {
  printf '%s' "$1" \
    | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()), end='')" 2>/dev/null \
    | sed 's/^"//;s/"$//' \
    || printf '%s' "$1"
}
