# ReShadeLinux

Bash installer that downloads the official ReShade runtime and shader packs and links them into
Wine/Proton game directories on Linux. Flow: scan Steam libraries -> pick a game -> download and verify
ReShade -> link the DLL, `d3dcompiler_47.dll` and a per-game merged shader directory into the game.
Interfaces: `yad` (GUI), `whiptail`/`dialog` (TUI) and a plain CLI, all over the same install logic.

## Commands

```bash
bash tests/run_simple_tests.sh                     # full suite; the merge gate
shellcheck $(git ls-files '*.sh')                  # lint; must report nothing (.shellcheckrc is picked up)
bash scripts/diagnostics/smoke_cli.sh              # isolated end-to-end CLI smoke test (CI runs it too)
bash scripts/diagnostics/smoke_whiptail.sh         # same for the whiptail backend (both need 7z installed)
./reshadelinux.sh --cli --game-path=DIR --dll-override=dxgi --shader-repos=none
./reshadelinux.sh --list-shader-repos              # prints the registry, exits
scripts/release/release-appimage.sh --build-only   # build and validate the AppImage, no side effects
```

The suite redirects `HOME`, `XDG_CACHE_HOME` and `MAIN_PATH` into a temp tree. Never point tests at a real Steam install.

## Layout

| Path | Role |
| --- | --- |
| `reshadelinux.sh` | Entrypoint. Sources `lib/*` and runs the install flow top to bottom. |
| `reshadelinux-gui.sh` | Wrapper that prefers the `yad` backend, then execs the entrypoint. |
| `lib/logging.sh` | Colours, `printStep`, `printErr` (exits the process), `logDebug`. |
| `lib/ui.sh` | Backend choice and the `ui_*` wrappers over yad/whiptail/dialog. |
| `lib/utils.sh` | `checkStdin`, `withProgress`, clipboard, temp-dir helpers. |
| `lib/cli.sh` | Flag parsing and validation. |
| `lib/config.sh` | `init_runtime_config`: defaults, `MAIN_PATH`, and the `SHADER_REPOS` registry. |
| `lib/state.sh` | Per-game state files under `$MAIN_PATH/game-state`, repo-selection helpers. |
| `lib/shader_registry.sh` | `SHADER_REPOS` entry parsing, labels, default/first-run/requested repo selection. |
| `lib/shader_build.sh` | Per-game merged shader directory: merge, link and header handling. |
| `lib/shaders.sh` | Repo clone/update, per-game `ReShade.ini`/preset, shader selection UI. |
| `lib/steam_detection.sh` | Steam roots and libraries, exe scoring, install-dir resolution. |
| `lib/steam_metadata.sh` | `appinfo.vdf` and PE import parsing (embedded Python), `detectSteamGames`. |
| `lib/game_selection.sh` | `getGamePath` and the manual path prompts. |
| `lib/install.sh` | Downloads and verification, DLL selection, linking into the game. |
| `lib/deps.sh` | Required-executable checks; reports all missing tools with per-manager install hints via `printErr`. |
| `lib/flow.sh` | Workspace init, ReShade version update, uninstall, batch update. |
| `tests/` | `run_simple_tests.sh`, `helpers/` (fixtures, loader), `suites/` (harness, exe, detection, state, shader, flow, deps, install, update, repos, ui, pe, release, release metadata, diagnostics, cli). |
| `scripts/diagnostics/` | Smoke tests and troubleshooting helpers. |
| `scripts/release/` | AppImage release tool. |
| `packaging/appimage/AppDir/` | AppRun, desktop entry, AppStream metainfo, icon. |

## Conventions

- `camelCase` function names. `_leadingUnderscore` for internal helpers and global state, `UPPER_SNAKE` for environment configuration.
- Every `lib/*.sh` starts with `# shellcheck shell=bash`, has no top-level side effects, and defines functions at top level only. A function defined inside another function or loop only exists after that code has run.
- Shipped scripts deliberately do not use `set -e`; every fallible call is checked explicitly. Code must still behave correctly when a caller runs it under `set -e` (the diagnostics and tests do): no bare `(( n++ ))`, and `var=$(cmd) || var=""` when "not found" is a normal outcome.
- `printErr` terminates the process. It cannot abort a caller from inside `$(...)`.
- All dialogs go through the `ui_*` wrappers, never `yad`/`whiptail`/`dialog` directly.
- Check `curl` and `git` failures explicitly. Do not add `2>/dev/null` to a fallible call without a `logDebug`.
- Comments explain why, not what. No commented-out code.

## Testing

- Add a regression test with every fix; write it first and watch it fail.
- Each test runs in a subshell under a real `set -e` (`_execute_test` in `run_simple_tests.sh`). Never call it from an `&&`, `||` or `if`: bash silently disables errexit there and only the last statement could fail the test. `tests/suites/harness_suite.sh` guards this.
- Register tests with `run_test "name" function`. Use `run_test_expect_fail` only for harness self-tests.
- Fixtures in `tests/helpers/fixtures.sh`: `setup_test_env`, `create_mock_game`, `create_mock_shader_repo`, `create_mock_pe` (synthetic PE with chosen imports), `assert_*`. Use real local git repositories for clone/update tests and a stubbed `PATH` for missing or fake programs (see `deps_suite.sh`).
- Tests that run flows reading runtime settings call `init_test_runtime_defaults`. To exercise a fatal path in a subshell, call `use_fatal_printErr` so `printErr` exits as it does in production.
- Stub external tools with function overrides or PATH stubs. Do not hit the network.
- To expect a failure use `assert_fails cmd ...`, never a bare `! cmd`: bash exempts negated commands from errexit, so the test would carry on and pass. A test scans the suites for it.

## Baselines

- File size: warn at 250 lines, hard limit 400. Decompose before extending a file over the limit.
- Runtime dependencies stay small: `7z curl file git python3` plus base tools (`grep sed sha256sum`). Propose removing one before adding another.
- Runtime is bash 5.x on Linux.

## Security notes

- ReShade downloads are restricted to the official hosts by `validateReshadeDownloadUrl`. `RESHADE_SETUP_SHA256` is an opt-in pin; without it the download is not hash-verified. `d3dcompiler_47.dll` is hash-pinned.
- Shader repos are third-party and cloned at their default-branch HEAD with no commit pinning. Treat registry additions as a review event.
- Never commit secrets or machine-specific paths.

## Release

- The version appears in `VERSION`, the fallback string in `reshadelinux.sh`, `X-AppImage-Version` in the desktop entry, the metainfo `<release>` list and `CHANGELOG.md`. Change them together; `scripts/release/check-version-sync.sh` (run by the tests and the release tool) fails if they disagree.
- `CHANGELOG.md` uses Keep a Changelog headings. The first *versioned* heading must match `VERSION` and be dated; an `## [Unreleased]` section above it is allowed.
- `scripts/release/release-appimage.sh --build-only` builds and validates the AppImage with no git or GitHub side effects. A real release must start on `main` with only the version files changed. `appimagetool` is pinned by checksum in `packaging/appimagetool.sha256`.
- Commits follow Conventional Commits (`fix:`, `feat:`, `test:`, `chore(release):`).

## Reference

- The official shader package list is `EffectPackages.ini` on the `list` branch of `crosire/reshade-shaders`. Compare `SHADER_REPOS` against it when auditing the registry.
- `docs/research/` holds unimplemented ideas (for example `--dry-run`, `--json`, `--no-input`).
