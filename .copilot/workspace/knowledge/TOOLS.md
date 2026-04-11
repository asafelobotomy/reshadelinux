# Tool Usage Patterns — reshade-steam

<!-- workspace-layer: L2 | trigger: tool query -->
> **Domain**: Inventory — CLI commands, tool usage patterns, and extension registry.
> **Boundary**: No preferences, reasoning, or project architecture facts.

*(Populated by Copilot from observed effective workflows. See §11 of `.github/copilot-instructions.md` for the full Tool Protocol.)*

## Core commands

| Tool / command | Effective usage pattern |
|----------------|-------------------------|
| `bash tests/run_simple_tests.sh` | Canonical underlying full-suite entrypoint when you need the direct command. |
| `echo "no type check configured"` | Run after every type definition change |
| `{{LOC_COMMAND}}` | Run after adding new files to check LOC bands |
| `bash tests/run_simple_tests.sh && echo "type-check: N/A"` | Preferred final verification command or ritual before marking any task done. |

If the repo documents a targeted-test selector or phase-test command, use it during intermediate phases instead of defaulting to the full suite.

## Toolbox

Custom-built and adapted tools are saved to `.copilot/tools/`. The catalogue is maintained in `.copilot/tools/INDEX.md`.

**Before writing any automation script**, always:

1. Check `.copilot/tools/INDEX.md` for an existing tool.
2. Follow §11 (Tool Protocol) in `.github/copilot-instructions.md` if no match is found.

The toolbox directory is created lazily — it does not exist until the first tool is saved.

## Discovered workflow patterns

*(Copilot appends effective multi-step tool workflows here as they become repeatable.)*

## Extension registry

*(Copilot appends new stack → extension mappings here when discovered during extension audits.)*

| Stack signal | Recommended extension(s) | Discovered | Quality (installs · rating) |
|-------------|--------------------------|------------|----------------------------|
