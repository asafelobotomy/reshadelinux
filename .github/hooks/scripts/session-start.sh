#!/usr/bin/env bash
# purpose:  Inject project context into every new agent session
# when:     SessionStart hook — fires when a new agent session begins
# inputs:   JSON via stdin (common hook fields)
# outputs:  JSON with additionalContext for the agent
# risk:     safe
# ESCALATION: none
set -euo pipefail

# shellcheck source=.github/hooks/scripts/lib-hooks.sh
source "$(dirname "$0")/lib-hooks.sh"

# Detect operating system and distro
OS_KERNEL=$(uname -s 2>/dev/null || echo "unknown")
OS_ARCH=$(uname -m 2>/dev/null || echo "unknown")
case "$OS_KERNEL" in
  Linux)
    OS_ID=$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
    OS_VERSION=$(grep '^VERSION_ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
    OS_VARIANT=$(grep '^VARIANT_ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
    # Detect immutable/atomic desktops
    if grep -qi 'ostree\|atomic\|immutable' /etc/os-release 2>/dev/null \
       || [[ -f /run/ostree-booted ]]; then
      OS_IMMUTABLE="true"
    else
      OS_IMMUTABLE="false"
    fi
    # Detect package manager
    if command -v apt &>/dev/null; then       PKG_MGR="apt"
    elif command -v pacman &>/dev/null; then   PKG_MGR="pacman"
    elif command -v dnf &>/dev/null; then      PKG_MGR="dnf"
    elif command -v rpm-ostree &>/dev/null; then PKG_MGR="rpm-ostree"
    elif command -v zypper &>/dev/null; then   PKG_MGR="zypper"
    elif command -v nix &>/dev/null; then      PKG_MGR="nix"
    elif command -v apk &>/dev/null; then      PKG_MGR="apk"
    else                                       PKG_MGR="unknown"
    fi
    OS_DISPLAY="${OS_ID}${OS_VARIANT:+/$OS_VARIANT} ${OS_VERSION} (${OS_ARCH})"
    ;;
  Darwin)
    OS_ID="macos"
    OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    OS_IMMUTABLE="false"
    PKG_MGR=$(command -v brew &>/dev/null && echo "brew" || echo "unknown")
    OS_DISPLAY="macOS ${OS_VERSION} (${OS_ARCH})"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    OS_ID="windows"
    OS_VERSION="n/a"
    OS_IMMUTABLE="false"
    PKG_MGR=$(command -v winget &>/dev/null && echo "winget" || echo "unknown")
    OS_DISPLAY="Windows/MSYS (${OS_ARCH})"
    ;;
  *)
    OS_ID="unknown"; OS_VERSION="unknown"; OS_IMMUTABLE="false"; PKG_MGR="unknown"
    OS_DISPLAY="${OS_KERNEL} (${OS_ARCH})"
    ;;
esac

# Gather project context
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
NODE_VER=$(node --version 2>/dev/null || echo "n/a")
PYTHON_VER=$(python3 --version 2>/dev/null | awk '{print $2}' || echo "n/a")

# Check for project manifest
if [[ -f package.json ]]; then
  PROJECT_NAME=$(python3 -c "import json; d=json.load(open('package.json')); print(d.get('name','unknown'))" 2>/dev/null || echo "unknown")
  PROJECT_VER=$(python3 -c "import json; d=json.load(open('package.json')); print(d.get('version','unknown'))" 2>/dev/null || echo "unknown")
elif [[ -f pyproject.toml ]]; then
  PROJECT_NAME=$(grep -m1 '^name' pyproject.toml | sed 's/.*= *"\(.*\)"/\1/' 2>/dev/null || echo "unknown")
  PROJECT_VER=$(grep -m1 '^version' pyproject.toml | sed 's/.*= *"\(.*\)"/\1/' 2>/dev/null || echo "unknown")
elif [[ -f Cargo.toml ]]; then
  PROJECT_NAME=$(grep -m1 '^name' Cargo.toml | sed 's/.*= *"\(.*\)"/\1/' 2>/dev/null || echo "unknown")
  PROJECT_VER=$(grep -m1 '^version' Cargo.toml | sed 's/.*= *"\(.*\)"/\1/' 2>/dev/null || echo "unknown")
else
  PROJECT_NAME=$(basename "$PWD")
  PROJECT_VER="n/a"
fi

# Check heartbeat pulse
PULSE="unknown"
if [[ -f .copilot/workspace/operations/HEARTBEAT.md ]]; then
  PULSE=$(grep -m1 'HEARTBEAT' .copilot/workspace/operations/HEARTBEAT.md 2>/dev/null | head -1 || echo "unknown")
fi

# Build compact specialist roster from routing manifest (fallback to defaults).
ROSTER=$(python3 - <<'PY'
import json
from pathlib import Path

default = {
  "agents": [
    {"name": "Code", "route": "active", "visibility": "picker-visible"},
    {"name": "Review", "route": "active", "visibility": "picker-visible"},
    {"name": "Fast", "route": "active", "visibility": "picker-visible"},
    {"name": "Audit", "route": "active", "visibility": "picker-visible"},
    {"name": "Commit", "route": "active", "visibility": "picker-visible"},
    {"name": "Explore", "route": "active", "visibility": "picker-visible"},
    {"name": "Organise", "route": "active", "visibility": "internal"},
    {"name": "Extensions", "route": "active", "visibility": "internal"},
    {"name": "Researcher", "route": "active", "visibility": "internal"},
    {"name": "Planner", "route": "active", "visibility": "internal"},
    {"name": "Docs", "route": "active", "visibility": "internal"},
    {"name": "Debugger", "route": "active", "visibility": "internal"},
    {"name": "Setup", "route": "guarded", "visibility": "picker-visible"},
  ]
}

manifest_path = Path('.github/agents/routing-manifest.json')
try:
  data = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else default
except Exception:
  data = default

direct, internal, guarded = [], [], []
for entry in data.get('agents', []):
  route = str(entry.get('route') or 'inactive')
  if route not in {'active', 'guarded'}:
    continue
  name = str(entry.get('name') or '').strip()
  if not name:
    continue
  if route == 'guarded':
    guarded.append(name)
  elif str(entry.get('visibility') or 'internal') == 'picker-visible':
    direct.append(name)
  else:
    internal.append(name)

parts = []
if direct:
  parts.append('specialists: ' + ', '.join(direct))
if internal:
  parts.append('internal: ' + ', '.join(internal))
if guarded:
  parts.append('guarded: ' + ', '.join(guarded))
print(' | '.join(parts) if parts else 'specialists: Code, Review, Fast, Audit, Commit, Explore | internal: Organise, Extensions, Researcher, Planner, Docs, Debugger | guarded: Setup')
PY
)

# Emit context for the agent — JSON-escape to handle special characters
CONTEXT="OS: ${OS_DISPLAY} | Pkg: ${PKG_MGR} | Immutable: ${OS_IMMUTABLE} | Project: ${PROJECT_NAME} v${PROJECT_VER} | Branch: ${BRANCH} (${COMMIT}) | Node: ${NODE_VER} | Python: ${PYTHON_VER} | Heartbeat: ${PULSE} | Routing: ${ROSTER}"
CONTEXT_ESC=$(json_escape "$CONTEXT")

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${CONTEXT_ESC}"
  }
}
EOF
