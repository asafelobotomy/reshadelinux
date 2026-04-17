# Bootstrap Record — reshadelinux

This workspace was scaffolded on **2026-04-10** using the [copilot-instructions-template](https://github.com/asafelobotomy/copilot-instructions-template).

## Initial stack detected

| Property | Value |
|----------|-------|
| Language | Bash/Shell |
| Runtime | bash 5.3 |
| Package manager | N/A |
| Test framework | custom bash (run_simple_tests.sh) |

## Files created during setup

| File | Action |
|------|--------|
| `.github/copilot-instructions.md` | Created from template + placeholders filled |
| `.github/agents/*.agent.md` | Created — model-pinned agent roster; exact inventory is tracked in `.copilot/workspace/operations/workspace-index.json` |
| `.github/skills/*/SKILL.md` | Created — reusable skill library (exact inventory tracked in `.copilot/workspace/operations/workspace-index.json`) |
| `.copilot/workspace/identity/IDENTITY.md` | Created |
| `.copilot/workspace/identity/SOUL.md` | Created |
| `.copilot/workspace/knowledge/USER.md` | Created |
| `.copilot/workspace/knowledge/TOOLS.md` | Created |
| `.copilot/workspace/knowledge/MEMORY.md` | Created |
| `.copilot/workspace/identity/BOOTSTRAP.md` | This file — created |
| `.copilot/workspace/operations/HEARTBEAT.md` | Created — event-driven health check checklist |
| `CHANGELOG.md` | Created / already existed |

## Toolbox

`.copilot/tools/` is created lazily — it does not exist until the first tool is saved by the agent. When it is created, `.copilot/tools/INDEX.md` will act as the catalogue.

## Skills

`.github/skills/` contains reusable workflow instructions following the [Agent Skills](https://agentskills.io) open standard. Starter skills were scaffolded during setup. New skills can be created via §12 or by saying "Create a skill for...".

*(This file is not updated after setup. It is a permanent record of origin.)*
