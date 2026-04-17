#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_DIR"
BASE="https://raw.githubusercontent.com/asafelobotomy/copilot-instructions-template/main"
OK_COUNT=0
FAIL_COUNT=0

fetch() {
  local url="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if curl -sSf "$url" -o "$dest"; then
    OK_COUNT=$((OK_COUNT + 1))
  else
    echo "FAIL: $url -> $dest"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

AGENTS="audit.agent.md coding.agent.md commit.agent.md debugger.agent.md docs.agent.md explore.agent.md extensions.agent.md fast.agent.md organise.agent.md planner.agent.md researcher.agent.md review.agent.md setup.agent.md routing-manifest.json"
for f in $AGENTS; do fetch "$BASE/.github/agents/$f" ".github/agents/$f"; done

SKILLS="agentic-workflows commit-preflight conventional-commit create-adr extension-review fix-ci-failure issue-triage lean-pr-review mcp-builder mcp-management plugin-management skill-creator skill-management test-coverage-review tool-protocol webapp-testing"
for skill in $SKILLS; do fetch "$BASE/template/skills/$skill/SKILL.md" ".github/skills/$skill/SKILL.md"; done

fetch "$BASE/template/hooks/copilot-hooks.json" ".github/hooks/copilot-hooks.json"
HOOK_SCRIPTS="guard-destructive.ps1 guard-destructive.sh heartbeat-policy.json heartbeat_clock_summary.py lib-hooks.sh mcp-heartbeat-server.py mcp-npx.sh mcp-uvx.sh post-edit-lint.ps1 post-edit-lint.sh pulse.ps1 pulse.sh pulse_intent.ps1 pulse_intent.py pulse_paths.ps1 pulse_paths.py pulse_runtime.ps1 pulse_runtime.py pulse_state.ps1 pulse_state.py save-context.ps1 save-context.sh scan-secrets.ps1 scan-secrets.sh session-start.ps1 session-start.sh subagent-start.ps1 subagent-start.sh subagent-stop.ps1 subagent-stop.sh"
for f in $HOOK_SCRIPTS; do fetch "$BASE/template/hooks/scripts/$f" ".github/hooks/scripts/$f"; done
chmod +x .github/hooks/scripts/*.sh 2>/dev/null

PROMPTS="explain.prompt.md context-map.prompt.md refactor.prompt.md test-gen.prompt.md review-file.prompt.md commit-msg.prompt.md onboard-commit-style.prompt.md"
for f in $PROMPTS; do fetch "$BASE/template/prompts/$f" ".github/prompts/$f"; done

INSTR="tests.instructions.md docs.instructions.md terminal.instructions.md config.instructions.md"
for f in $INSTR; do fetch "$BASE/template/instructions/$f" ".github/instructions/$f"; done

fetch "$BASE/template/copilot-setup-steps.yml" ".github/workflows/copilot-setup-steps.yml"

WORKSPACE="identity/IDENTITY.md identity/SOUL.md identity/BOOTSTRAP.md knowledge/USER.md knowledge/TOOLS.md knowledge/MEMORY.md knowledge/MEMORY-GUIDE.md knowledge/RESEARCH.md knowledge/diaries/README.md operations/commit-style.md operations/HEARTBEAT.md operations/ledger.md operations/workspace-index.json"
for f in $WORKSPACE; do fetch "$BASE/template/workspace/$f" ".copilot/workspace/$f"; done

fetch "$BASE/template/CLAUDE.md" "CLAUDE.md"

echo "OK: $OK_COUNT, FAIL: $FAIL_COUNT"
