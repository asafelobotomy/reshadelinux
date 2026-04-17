# Memory Strategy — reshadelinux

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
|CHANGELOG.md must NOT use `## [Unreleased]` headings — tests assert the first `## [` entry matches `VERSION` and is dated. Adding `[Unreleased]` breaks `test_release_metadata_*` tests.|`tests/suites/state_shader_suite.sh:454`, `tests/suites/state_shader_suite.sh:466`|High|2026-04-10|
|The canonical reference for which shader repos to include in `SHADER_REPOS` is the official ReShade installer package list: `https://raw.githubusercontent.com/crosire/reshade-shaders/list/EffectPackages.ini` (the `list` branch). Check this URL when auditing or expanding shader coverage.|`lib/config.sh`, `lib/shaders.sh`|High|2026-04-17|
|Display titles now live directly in the five-field `SHADER_REPOS` entries in `lib/config.sh`, and `parseShaderRepoEntry` remains backward-compatible with older four-field overrides that omit the title. The same GitHub URL can still appear twice with different local names when targeting different branches (e.g. `reshade-shaders` on `slim` and `reshade-shaders-legacy` on `legacy`).|`lib/config.sh`, `lib/shaders.sh`|High|2026-04-17|
|Workspace governance files are canonical under `.copilot/workspace/identity/`, `.copilot/workspace/knowledge/`, and `.copilot/workspace/operations/`; human-facing hooks and instructions should use full paths instead of bare filenames.|`.copilot/workspace/identity/BOOTSTRAP.md`, `.copilot/workspace/operations/workspace-index.json`|High|2026-04-10|

## Known Gotchas

|Gotcha|Affected files|Workaround|Observed|
|---|---|---|---|
|`dialog` radiolists do not behave like `whiptail` under automation: pressing `Tab` before `Enter` moves focus to `Cancel`, so smoke feeders must use `Enter` to accept the default selection and should set a fallback `TERM` in clean-room runs.|`scripts/diagnostics/smoke_dialog.sh`|Verify widget key semantics with a minimal reproduction before scripting the full flow; default `TERM` when running under `env -i`.|2026-04-10|
|The built-in fast search helper can be unavailable even when local search agents are configured and routed; this is a runtime/platform availability issue, not necessarily a repo misconfiguration.|`.github/agents/explore.agent.md`, `.github/agents/routing-manifest.json`, `.vscode/settings.json`|Verify local agent routing and settings first, then fall back to `runSubagent` with `Explore` or direct searches instead of rewriting repo config.|2026-04-10|

## Archived

- 2026-04-11: Path identification for `/mnt/SteamLibrary/git/reshadelinux` was verified with SHA256-based directory association.
- 2026-04-11: Local processes can write to `.copilot/workspace/runtime` even when the sandbox reports a read-only root filesystem.

