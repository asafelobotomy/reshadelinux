# Scripts

Repository support scripts are grouped here so the top level stays focused on the main entrypoints, libraries, tests, and packaging assets.

## Diagnostics

These scripts are for local investigation and manual verification. They source the production libraries through `diagnostics/common.sh` instead of scraping partial content from `reshade-linux.sh`.

- `diagnostics/check_libs.sh` - lists discovered Steam libraries and manifest duplicates
- `diagnostics/audit_shaders.sh` - clones each configured shader repo into a temp workspace and verifies layout discovery plus merged per-game shader output
- `diagnostics/debug_games.sh` - dumps detected games and duplicate AppIDs
- `diagnostics/smoke_cli.sh` - runs isolated end-to-end CLI smoke coverage for manual install, Steam autodetect install, shader clone retry handling, and seeded `--update-all`
- `diagnostics/smoke_dialog.sh` - runs an isolated dialog-backed install smoke test without depending on the missing `script` utility
- `diagnostics/test_detection.sh` - runs Steam detection and prints a simple report
- `diagnostics/test_yad_menu.sh` - shows the menu items that would be passed to the game picker UI
