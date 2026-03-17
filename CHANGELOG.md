# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, adapted for this repository.

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

- `reshade-linux.sh` now reads its displayed version from `VERSION`, with a fallback for standalone script downloads.
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
