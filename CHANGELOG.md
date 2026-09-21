# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, adapted for this repository.

## [Unreleased]

### Added

- The shader picker on the graphical interface has **Select all** and **Select none** buttons (Alt+A and Alt+N). Two more scenarios in `smoke_yad.sh` cover them.

### Changed

- Messages that report a problem (a path that does not exist, an unsupported DLL name, packs that could not be downloaded) use a warning icon instead of the information icon.
- Output is coloured only on a terminal, so logs and pipes stay readable. `NO_COLOR` turns colour off and `CLICOLOR_FORCE=1` turns it on for a pipe.

### Fixed

- `reshadelinux-gui.sh` opens the terminal fallback (added in 1.3.4) only for a launch without arguments, which is what a menu launch is. A run with arguments, such as a script or the release tool's `--update-all` check on a machine with a display and a terminal emulator, no longer gets a terminal window that waits for Enter.

## [1.3.4] - 2026-09-21

### Fixed in 1.3.4

- Graphical interface: message, question and error dialogs never appeared on current yad (yad 15 has no `--info`, `--question` or `--error` and the wrapper hid its complaint). The shader download and installation-complete dialogs were missing, fatal errors were invisible under the GUI, and every yes/no question was silently answered No. They now use plain dialogs with an icon and buttons, and yad's own messages go to the debug log.
- Graphical interface: choosing "Uninstall" or "Update all" by clicking its label and pressing OK started an install instead, because the action list was a radio list that keeps its pre-selected radio. Single-choice lists now answer with the highlighted row.
- Graphical interface: game and pack names containing `<` or `>` were corrupted on bash 5.2 and newer (an unquoted `&` in a bash replacement means "the matched text").
- Graphical interface: uninstall and update-all now finish with a dialog (the folder that was cleaned, the number of games updated and skipped). Before, the result was printed only to a terminal that a menu launch does not have. whiptail and dialog keep the terminal summary and get no extra dialog.
- Graphical interface: Enter on a question answers Yes, as in whiptail and dialog.
- An existing `ReShade.ini` that is a symlink (shared between games) is updated in place when its search paths are corrected. Version 1.3.3 replaced the link with a copy.
- Graphical interface: dialogs, including the fatal-error dialog, still open when the temporary directory is full or unwritable; before, yad's message capture failed first and nothing appeared.
- Graphical interface: the terminal fallback of `reshadelinux-gui.sh` passes on the installer's own exit status (read back from the terminal run, because xterm and others always exit 0) and no longer starts the install a second time in another terminal emulator after a cancel or an error.
- `ui_menu` no longer aborts when its caller runs under `set -e`.
- Launching `reshadelinux-gui.sh` from the application menu without `yad` used to do nothing visible. It now opens a terminal emulator for the text interface (or shows a desktop notification when there is none).

### Added in 1.3.4

- `scripts/diagnostics/smoke_yad.sh`: an opt-in smoke test that drives the real yad dialogs end to end on a private X server, plus an experimental `gui-smoke` CI job that runs it on Ubuntu 22.04 and 24.04.
- `docs/testing/`: smoke checklists for launch and packaging, every GUI dialog in order, the manage flows, dialog behaviour, the terminal interfaces, shader packs in a real game, errors and edge cases, and a short release pass, with the audit that produced them.
- `scripts/diagnostics/compile_check.sh`, an opt-in check that runs the real ReShade under GE-Proton against the merged shader directory of any packs and reports which effects compile. It is how the 1.3.3 fixes were found and verified. It downloads pinned, checksum-verified tools into its own cache directory, never touches the real workspace, and is not part of CI.

## [1.3.3] - 2026-09-21

### Added in 1.3.3

- 25 more shader packs (69 in total), all checked for a compatible layout, resolvable `#include`s and no bundled binaries or download links: Glamarye Fast Effects, lordbean Shaders, RenoFX, Optical Flow, ZealShaders, murchFX, QuarkFX, fakebilinear2, shaman Shaders, KaiserThompson Shaders, QD-OLED APL Fixer, RSJankShaders, RSUnityShaders, ReshadeTFAA, ReshadeMotionEstimation, ReshadeBUR, CRT-Standalone, CRT-Dusha, Filmic Tonemapping, Zackin5 Misc Shaders, guestrr Shaders, Smart Vibrance, LXAA, Fast Adaptive AA and DeTintX. Several have not been updated for years but still compile against current ReShade.
- Packs that keep their effects at the repository root instead of in a `Shaders/` folder (most single-shader repos) are now installed; previously nothing was linked. Only `.fx` and `.fxh` files are linked, keeping their relative paths, and a `Shaders/` folder still takes precedence.

- Packs can declare that they need other packs (a sixth `requires` field in a registry entry). Ann-ReShade needs CShade, BFBFX needs ZenteonFX, ReshadeTFAA and Shades need iMMERSE (LAUNCHPAD), Optical Flow needs qUINT and lordbean Shaders need SweetFX; selecting one now clones and merges what it needs.
- `SHADER_CORE_REPOS` (default `reshade-shaders`) and `SHADER_BROKEN_EFFECTS` settings, see the README.

### Fixed in 1.3.3

- Effects in subfolders of a shader pack never appeared in ReShade: SweetFX's 28 effects, CameraFilterPack, SHADERDECK and about 30 more, roughly one effect in ten. The generated `ReShade.ini` named the merged folders without the `\**` suffix ReShade needs to search subfolders. New files use it, and an `ReShade.ini` this installer wrote earlier is corrected the next time the game is installed or updated. Search path lists you edited are left alone.
- A shader pack selected on its own did not compile (`could not open included file 'ReShade.fxh'`) because only the selected packs were cloned and the headers live in Standard Effects. That pack is now always cloned and its headers linked, without adding its effects.
- Effects that fail to compile with ReShade 6.8 on Proton no longer show an error in every game: `GrainSpread`, `NTSCCustom`, `NTSC_XOT`, `BX_XIV_ChromakeyPlus`, `TrooCullers`, `OilPaint` and `ZenWork` are left out. This was found by running every pack under GE-Proton; the first four were already excluded for The Elder Scrolls Online only.
- When two packs ship different copies of the same header (BFBFX and ZenteonFX both have `ZenteonCommon.fxh`, and RSUnity and GShade both have `RetroTV.fxh`), the build now warns that the first copy is used for both.
- Shader packs whose content folders are not named exactly `Shaders` and `Textures` are now found. CShade moved to a lowercase `shaders/` folder, so selecting it linked nothing; ReShade under Wine ignores case, so upstream authors never notice. Lookup now accepts any case and prefers an exact match, for repositories and for `External_shaders`.
- The shader audit diagnostic reuses the installer's folder lookup instead of its own copy, so the two cannot disagree.

### Changed in 1.3.3

- The Barbatos shader pack now points at its current GitHub owner, `BarbatosAWLS`. The old `BarbatosBachiko` account no longer exists and only redirected.

## [1.3.2] - 2026-09-19

### Fixed in 1.3.2

- Steam detection no longer drops games whose only executable name merely contains a helper word, such as `reach.exe`, `latest.exe`, `teacher.exe` or `aspect.exe`. Helper names are now matched as words.
- A missing required program now shows an error dialog under the GUI and the AppImage (previously the app exited with no message), lists every missing program at once, and gives the correct package name for pacman and apt. Where the name could not be verified for dnf or zypper it prints a package-search command instead.
- A failed or interrupted ReShade download no longer removes the working `latest` link, a lost link is repaired, and a recorded version whose files are missing on disk is downloaded again.
- `--update-all` with no tracked games now exits before contacting reshade.me or requiring `7z`.
- The manual DLL override prompt now accepts the same names as `--dll-override` and `--update-all`, so a game installed with a hand-typed DLL is no longer skipped by later batch updates. It also stops instead of looping forever when input closes.
- Executables larger than about 2 MiB are now analysed correctly, so the DLL override is no longer guessed for large games. Python helper errors are written to the debug log.
- Shader repository updates no longer stop on a credentials prompt, give up on a stalled connection, and recover when an upstream repository rewrote its history, but only when the local clone has no edits, commits or untracked files.
- A build with no shader repositories selected and no external shaders no longer prints `command not found` twice.
- Temporary directories are removed when a fatal error ends the run.
- A real `ReShade_shaders` folder in a game directory is moved aside to `ReShade_shaders.bak-<timestamp>` instead of being deleted.
- yad dialogs show paths and messages literally, so a game path containing `&` or `<` no longer breaks the dialog.
- The diagnostics scripts that load the libraries (`test_detection.sh`, `check_libs.sh`, `debug_games.sh`) work again.

### Security in 1.3.2

- `RESHADE_SETUP_SHA256` is compared literally. Previously a glob value such as `*` matched any file. Values that are not a 64-character hex digest are rejected.
- The ReShade download URL check accepts only the exact `ReShade_Setup_<version>[_Addon].exe` address on the official hosts, rejecting path, query and fragment tricks.
- The release tool downloads a pinned `appimagetool` release with `gh` and verifies its SHA-256 before running it.

### Added in 1.3.2

- `EXTRA_DLL_OVERRIDES` extends the accepted DLL override names.
- Two shader packs from the official ReShade list: Shades by JakobPCoder and verfx Shaders by vertver.
- `scripts/release/release-appimage.sh --build-only` builds and validates the AppImage with no git or GitHub side effects, and a release run now requires `main` with only the version files changed.
- The command-line options `--cli`, `--ui-backend`, `--game-path`, `--app-id`, `--dll-override`, `--shader-repos` and `--list-shader-repos` are documented in the changelog for the first time; they arrived during 1.3.1 development.
- `SECURITY.md`, `CONTRIBUTING.md`, `.editorconfig`, a Dependabot configuration, and a `.shellcheckrc`.

### Changed in 1.3.2

- The test runner now fails a test when any assertion in it fails. Before, only the last statement counted, so several tests passed while checking nothing. The suite grew from 101 to over 200 tests.
- `UI_AUTO_CONFIRM` prints a warning when it is active.
- Internals were split into smaller modules (`shader_registry.sh`, `shader_build.sh`, `deps.sh`) and the whole tree is ShellCheck-clean.
- CI runs on Ubuntu 22.04 and 24.04, lints with ShellCheck, runs the CLI and whiptail smoke tests, validates the AppStream and desktop files, uses a read-only token and a commit-pinned checkout action.
- The smoke tests keep their workspace and print their logs when a run fails, instead of deleting them.
- The Copilot agent scaffolding was removed; `CLAUDE.md` is now self-contained.

## [1.3.1] - 2026-04-17

### Changed in 1.3.1

- AppImage startup now goes through `reshadelinux-gui.sh`, so packaged launches use the same GUI backend fallback path as direct script launches.
- AppImage release validation now exercises startup with `--update-all` instead of checking `--help` only.

### Fixed in 1.3.1

- Forced UI backend selection now fails immediately when the requested backend command is missing.
- TUI and CLI dependency checks now run by operation phase, so uninstall and game-selection flows do not require download tooling up front.
- ReShade downloads now accept only the expected official hosts, support optional `RESHADE_SETUP_SHA256` pinning, and verify the extracted DLL payload before install.

## [1.3.0] - 2026-03-17

### Added in 1.3.0

- "Update all installed games" option in the install/uninstall dialog, so users no longer need the `--update-all` CLI flag.
- Copilot instructions factory-restored from [copilot-instructions-template](https://github.com/asafelobotomy/copilot-instructions-template) v5.10.0 (upgraded from v3.3.2). Pre-restore backup at `.github/archive/pre-factory-restore-2026-04-10-v3.3.2/`.

### Fixed in 1.3.0

- Shader compilation failures when a repo containing shared `.fxh` headers (e.g. `ReShade.fxh`, `ReShadeUI.fxh`) was not selected. Include files from all installed repos are now always linked.

## [1.2.1] - 2026-03-17

### Changed in 1.2.1

- The VS Code `dialog-smoke-repro` task now uses `scripts/diagnostics/smoke_dialog.sh`, which avoids a hard dependency on the util-linux `script` command.
- Diagnostics and test helpers now include explicit ShellCheck hints so repository-wide shell analysis passes cleanly.
- Verification was re-run for the current codebase: shell tests, ShellCheck, and dialog smoke all pass in this environment.

## [1.2.0] - 2026-03-12

### Added in 1.2.0

- Single-source versioning via the top-level `VERSION` file.
- `printErr()` helper for consistent fatal error handling.
- On-disk install verification so Steam games are only marked installed when the recorded ReShade DLL still exists.
- Rich shader repository descriptions in the selector UI.
- Shell-test CI workflow after removal of the previous BATS-based setup.

### Changed in 1.2.0

- `reshadelinux.sh` now reads its displayed version from `VERSION`, with a fallback for standalone script downloads.
- Shader repository defaults expanded from 6 to 18 curated repos with human-readable descriptions.
- Shader checklist sizing now adapts to terminal height.
- Game install-directory resolution now tries root directories last instead of first.
- README reorganised and expanded for clearer feature and configuration documentation.
- Vulkan comments now reflect the current experimental and unmaintained state of that code path.

### Fixed in 1.2.0

- False "installed" indicators caused by stale state files with missing ReShade DLLs.
- Test helper executable scoring drift relative to the main script.

### Removed in 1.2.0

- Unused `applyLaunchOption()` implementation.
- Unused `steamIsRunning()` helper.
- Empty `# Z0020` section marker.
- Redundant single-use `_launchOpt` variable.
- Legacy BATS test suite and related test files.

## [1.1.0] - 2026-03-11

### Added in 1.1.0

- PE import-table based DLL override detection instead of defaulting blindly to `dxgi`.
- Per-game state files in `game-state/<appid>.state`.
- Installed-game indicators in the game picker.
- `--update-all` for re-linking all tracked games without prompts.
- Built-in preset for Oblivion Remastered.
- Test suite and repository `.gitignore` cleanup.

### Changed in 1.1.0

- README updated to document the new workflow, environment variables, and batch update mode.
- Script version bumped from `1.0.2` to `1.1.0`.

## [1.0.2] - 2026-03-04

### Fixed in 1.0.2

- AppImage FUSE3 compatibility by switching to `type2-runtime`.
- CI environment updated to Ubuntu 22.04.

## [1.0.1] - 2026-03-04

### Fixed in 1.0.1

- AppImage GUI launch by setting `Terminal=false`, forcing `_GUI=1`, and logging stderr.

## [1.0.0] - 2026-03-04

### Fixed in 1.0.0

- Release workflow YAML block-scalar parsing failure that broke tagged releases.

### Changed in 1.0.0

- Release notes generation moved to a dedicated file-based step for reliable GitHub release creation.
