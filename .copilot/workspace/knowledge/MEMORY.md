# Memory Strategy — reshade-steam

<!-- workspace-layer: L1 | budget: ≤300 tokens | trigger: always -->
> **Domain**: Facts — verified project facts, error patterns, team conventions, baselines, and gotchas.
> **Boundary**: No opinions, preferences, reasoning heuristics, or session-specific state.
> **Guide**: See `MEMORY-GUIDE.md` for principles, coexistence rules, and maintenance protocol.

## Architectural Decisions

|Date|Decision|Rationale|Status|Source|
|---|---|---|---|---|
||||||

## Recurring Error Patterns

|Error signature|Root cause|Fix pattern|Last seen|
|---|---|---|---|
|||||

## Team Conventions Discovered

|Convention|Source|Confidence|Date learned|
|---|---|---|---|
|CHANGELOG.md must NOT use `## [Unreleased]` headings — tests assert the first `## [` entry matches `VERSION` and is dated. Adding `[Unreleased]` breaks `test_release_metadata_*` tests.|`tests/test_state_shader_groups.sh:243`|High|2026-04-10|
|Workspace governance files are canonical under `.copilot/workspace/identity/`, `.copilot/workspace/knowledge/`, and `.copilot/workspace/operations/`; human-facing hooks and instructions should use full paths instead of bare filenames.|`.copilot/workspace/identity/BOOTSTRAP.md`, `.copilot/workspace/operations/workspace-index.json`|High|2026-04-10|

## Known Gotchas

|Gotcha|Affected files|Workaround|Observed|
|---|---|---|---|
|`dialog` radiolists do not behave like `whiptail` under automation: pressing `Tab` before `Enter` moves focus to `Cancel`, so smoke feeders must use `Enter` to accept the default selection and should set a fallback `TERM` in clean-room runs.|`scripts/diagnostics/smoke_dialog.sh`|Verify widget key semantics with a minimal reproduction before scripting the full flow; default `TERM` when running under `env -i`.|2026-04-10|
|The built-in fast search helper can be unavailable even when local search agents are configured and routed; this is a runtime/platform availability issue, not necessarily a repo misconfiguration.|`.github/agents/explore.agent.md`, `.github/agents/routing-manifest.json`, `.vscode/settings.json`|Verify local agent routing and settings first, then fall back to `runSubagent` with `Explore` or direct searches instead of rewriting repo config.|2026-04-10|

## Archived

|Entry|Archived|Reason|
|---|---|---|
- Path identification: Used SHA256 hashing to verify directory associations.
- Environment: Working in /mnt/SteamLibrary/git/reshade-steam.
Session concluded. Directory /mnt/SteamLibrary/git/reshade-steam matches hash e1004a8ce8d5.
- Completed execution of test suite for reshade-steam project.
- Verified that all 80 tests in 'tests/run_simple_tests.sh' pass.
### Session Reflection: Sat Apr 11 01:09:24 AM BST 2026
- Verified writability of .copilot/workspace/runtime.
- Confirmed that local processes have write access to the workspace runtime directory, even when the sandbox reports a read-only root filesystem.
- Directory ownership: merlin:merlin (1000:1000).

