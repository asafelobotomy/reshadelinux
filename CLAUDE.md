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
bash scripts/diagnostics/smoke_yad.sh               # opt-in: real yad dialogs on a private X server (needs yad, Xvfb, xdotool)
bash scripts/diagnostics/compile_check.sh --packs NAME  # opt-in: real ReShade under GE-Proton compiles the merged effects (about 4 GB, not for CI)
./reshadelinux.sh --cli --game-path=DIR --dll-override=dxgi --shader-repos=none
./reshadelinux.sh --list-shader-repos              # prints the registry, exits (--json for JSON)
./reshadelinux.sh --dry-run --no-input --game-path=DIR   # prints the plan, changes nothing
scripts/release/pin-shader-repos.sh --check        # which shader packs moved upstream since they were pinned
scripts/release/release-appimage.sh --build-only   # build and validate the AppImage, no side effects
```

The suite redirects `HOME`, `XDG_CACHE_HOME` and `MAIN_PATH` into a temp tree. Never point tests at a real Steam install.

## Layout

`reshadelinux.sh` is the entrypoint (sources `lib/*`, runs the install flow); `reshadelinux-gui.sh` wraps it preferring yad; `tests/`, `scripts/diagnostics/`, `scripts/release/`, `docs/testing/` (manual smoke checklists: update them with any user-visible change), `packaging/appimage/AppDir/`. Full file-by-file table: `docs/agents/layout.md`.

## Conventions

- `camelCase` function names. `_leadingUnderscore` for internal helpers and global state, `UPPER_SNAKE` for environment configuration.
- Every `lib/*.sh` starts with `# shellcheck shell=bash`, has no top-level side effects, and defines functions at top level only. A function defined inside another function or loop only exists after that code has run.
- Shipped scripts deliberately do not use `set -e`; every fallible call is checked explicitly. Code must still behave correctly when a caller runs it under `set -e` (the diagnostics and tests do): no bare `(( n++ ))`, and `var=$(cmd) || var=""` when "not found" is a normal outcome.
- `printErr` terminates the process with status 1; `failWith "$EXIT_USAGE" ...` picks one of the documented statuses. Neither can abort a caller from inside `$(...)`. Never renumber an `EXIT_*` status.
- Anywhere the program would ask the user something, call `requireInput "<what is missing and which flag supplies it>"` first, or skip the question under `isNoInput`.
- A dynamic value (path, name, message) put into dialog text goes through `uiQuote`; the `\n` in our own strings are the only escapes yad should see.
- All dialogs go through the `ui_*` wrappers, never `yad`/`whiptail`/`dialog` directly. yad has no `--info`/`--question`/`--error` dialog kinds in current releases: message dialogs are plain dialogs with `--image` and `--button`. Never discard yad's stderr; `_ui_yad_run` and `ui_capture` send it to the debug log.
- Check `curl` and `git` failures explicitly. Do not add `2>/dev/null` to a fallible call without a `logDebug`.
- Comments explain why, not what. No commented-out code.

## Testing

- Add a regression test with every fix; write it first and watch it fail.
- To expect a failure use `assert_fails cmd ...`, never a bare `! cmd`: bash exempts negated commands from errexit, so the test would carry on and pass. A test scans the suites for it.
- Test harness rules (errexit subshells, `run_test`, fixtures, stubs): `docs/agents/testing.md`.

## Baselines

- File size: warn at 250 lines, hard limit 400. Decompose before extending a file over the limit.
- Runtime dependencies stay small: `7z curl file git python3` plus base tools (`grep sed sha256sum`). Propose removing one before adding another.
- Runtime is bash 5.x on Linux.

## Security notes

- ReShade downloads are restricted to the official hosts by `validateReshadeDownloadUrl` and verified against `lib/reshade_pins.sh` (or `RESHADE_SETUP_SHA256`). An unpinned build is refused unless `RESHADE_ALLOW_UNPINNED=1`; `latest` falls back to the newest pinned build. `d3dcompiler_47.dll` is hash-pinned.
- Built-in shader repos are checked out at the commit in `lib/shader_pins.sh`. A clone with the user's edits or commits is never moved. Adding a pack or re-pinning (`scripts/release/pin-shader-repos.sh`, review the printed compare links) is a review event. `tests/suites/pinning_suite.sh` fails when a built-in pack has no pin.
- Never commit secrets or machine-specific paths.

## Release, reference

Commits follow Conventional Commits (`fix:`, `feat:`, `test:`, `chore(release):`). Version files must stay in sync (`scripts/release/check-version-sync.sh`). Release steps, pins and the shader-registry audit reference: `docs/agents/release-and-reference.md`.
