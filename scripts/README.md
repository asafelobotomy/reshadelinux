# Scripts

Repository support scripts are grouped here so the top level stays focused on the main entrypoints, libraries, tests, and packaging assets.

## Diagnostics

These scripts are for local investigation and manual verification. Shared sourcing and reporting helpers now live under `diagnostics/helpers/` instead of mixing infrastructure files with runnable scripts.
All smoke diagnostics share `diagnostics/helpers/smoke_common.sh` for runtime workspace setup and assertions. The backend-specific TUI smoke runners layer on `diagnostics/helpers/smoke_tui_common.sh` so dialog and whiptail coverage stay aligned.

- `diagnostics/check_libs.sh` - lists discovered Steam libraries and manifest duplicates
- `diagnostics/audit_shaders.sh` - clones each configured shader repo into a temp workspace and verifies layout discovery plus merged per-game shader output
- `diagnostics/debug_games.sh` - dumps detected games and duplicate AppIDs
- `diagnostics/helpers/common.sh` - shared production-library sourcing for diagnostics that inspect real Steam state
- `diagnostics/helpers/smoke_common.sh` - shared runtime workspace setup and assertions for smoke diagnostics
- `diagnostics/helpers/smoke_tui_common.sh` - shared dialog/whiptail smoke orchestration layered on the smoke base helpers
- `diagnostics/helpers/steam_report_common.sh` - shared manifest parsing and detected-game reporting helpers used by Steam inspection diagnostics
- `diagnostics/smoke_cli.sh` - runs isolated end-to-end CLI smoke coverage for manual install, Steam autodetect install, shader clone retry handling, and seeded `--update-all`
- `diagnostics/smoke_cli_no_cleanup.sh` - runs the same CLI smoke suite but keeps the temp workspace for postmortem inspection
- `diagnostics/smoke_cli_no_trap.sh` - compatibility wrapper that routes older shell history through the maintained no-cleanup CLI smoke path
- `diagnostics/smoke_dialog.sh` - runs an isolated dialog-backed install smoke test without depending on the missing `script` utility
- `diagnostics/smoke_whiptail.sh` - runs an isolated whiptail-backed install smoke test using the shared auto-answer UI path
- `diagnostics/test_detection.sh` - runs Steam detection and prints a simple report
- `diagnostics/test_dialog.sh` - compatibility wrapper that preserves the historical dialog test entrypoint by delegating to `smoke_dialog.sh`
- `diagnostics/test_yad_menu.sh` - shows the menu items that would be passed to the game picker UI

## Setup

These scripts manage repository scaffolding and maintenance rather than product runtime behavior.

- `setup/sync-copilot-template.sh` - refreshes the repo's Copilot agents, skills, hooks, prompts, instructions, and workspace files from the upstream template
