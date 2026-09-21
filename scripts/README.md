# Scripts

Repository support scripts are grouped here so the top level stays focused on the main entrypoints, libraries, tests, and packaging assets.

## Diagnostics

These scripts are for local investigation and manual verification. Shared sourcing and reporting helpers now live under `diagnostics/helpers/` instead of mixing infrastructure files with runnable scripts.
All smoke diagnostics share `diagnostics/helpers/smoke_common.sh` for runtime workspace setup and assertions. The backend-specific TUI smoke runners layer on `diagnostics/helpers/smoke_tui_common.sh` so dialog and whiptail coverage stay aligned.

- `diagnostics/check_libs.sh` - lists discovered Steam libraries and manifest duplicates
- `diagnostics/audit_shaders.sh` - clones each configured shader repo into a temp workspace and verifies layout discovery plus merged per-game shader output
- `diagnostics/compile_check.sh` - opt-in: runs the real ReShade under GE-Proton against the merged shader directory and reports which effects compile (`--packs`, `--software`, `--include-broken`, `--purge`). Downloads pinned GE-Proton and llvm-mingw builds into `~/.cache/reshadelinux-compile-check` (about 4 GB with every pack), opens a small window while it runs, and takes 5-15 minutes for all packs. Not for CI. Exit 0 pass, 1 an effect failed, 2 it could not run (for example ReShade never started: try `--software`, which needs the lavapipe Vulkan driver).
- `diagnostics/smoke_yad.sh` - opt-in: drives the real yad dialogs end to end on a private X server (Xvfb, xdotool, optionally openbox) and checks what each flow leaves behind: install, cancels, a game with `&` and `<` in its name, an unsupported DLL name, no shader packs, a failed clone with retry, uninstall, update-all and a fatal error dialog. Set `SMOKE_YAD_SHOTS=DIR` to keep a screenshot of every dialog. It never touches your desktop or a real Steam library. The manual counterpart is [`docs/testing`](../docs/testing/README.md).
- `diagnostics/debug_games.sh` - dumps detected games and duplicate AppIDs
- `diagnostics/helpers/common.sh` - shared production-library sourcing for diagnostics that inspect real Steam state
- `diagnostics/helpers/compile_check_report.py` - reads a `ReShade.log` and lists compiled, failed and unreported effects (covered by `tests/suites/compile_check_suite.sh`)
- `diagnostics/helpers/d3dtest.cpp` - the tiny D3D11 program the compile check builds with mingw so ReShade has something to attach to
- `diagnostics/helpers/smoke_yad_common.sh` - the yad smoke driver: private X server, dialog waiting by process (X11 reuses window ids), keystroke helpers, and a fake Steam library with a stub `7z`
- `diagnostics/helpers/smoke_common.sh` - shared runtime workspace setup and assertions for smoke diagnostics
- `diagnostics/helpers/smoke_tui_common.sh` - shared dialog/whiptail smoke orchestration layered on the smoke base helpers
- `diagnostics/helpers/steam_report_common.sh` - shared manifest parsing and detected-game reporting helpers used by Steam inspection diagnostics
- `diagnostics/smoke_cli.sh` - runs isolated end-to-end CLI smoke coverage (set `SMOKE_KEEP_WORKSPACE=1` to keep the temp workspace; a failing run always keeps it and prints the tail of each log) for manual install, Steam autodetect install, shader clone retry handling, and seeded `--update-all`
- `diagnostics/smoke_dialog.sh` - runs an isolated dialog-backed install smoke test without depending on the missing `script` utility
- `diagnostics/smoke_whiptail.sh` - runs an isolated whiptail-backed install smoke test using the shared auto-answer UI path
- `diagnostics/test_detection.sh` - runs Steam detection and prints a simple report
- `diagnostics/test_yad_menu.sh` - shows the menu items that would be passed to the game picker UI

## Release

- `release/release-appimage.sh` - validates the repository, builds the AppImage, and publishes a release from the current `VERSION` and `CHANGELOG.md`. Use `--build-only` for a build with no commit, tag, push or GitHub changes. A release run must start on `main` with only the version files changed.
- `release/lib-release.sh` - helper functions for the release tool (sourced, and covered by `tests/suites/release_suite.sh`)
- `release/check-version-sync.sh` - verifies that `VERSION`, the changelog, the AppStream metainfo, the `reshadelinux.sh` fallback and the desktop entry agree
