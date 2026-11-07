# Layout

Moved from CLAUDE.md. Read when you need to find which file owns a behaviour.

| Path | Role |
| --- | --- |
| `reshadelinux.sh` | Entrypoint. Sources `lib/*` and runs the install flow top to bottom. |
| `reshadelinux-gui.sh` | Wrapper that prefers the `yad` backend, then execs the entrypoint. |
| `lib/logging.sh` | Colours, exit statuses (`EXIT_*`), `printStep`, `printWarn` (stderr), `printErr`/`failWith` (exit the process), `--quiet` output, `logDebug`. |
| `lib/ui.sh` | Backend choice and the `ui_*` wrappers over yad/whiptail/dialog. |
| `lib/ui_yad.sh` | yad specifics: `uiQuote`, pango escaping, sizes, logged runs, message dialogs, the progress window. |
| `lib/ui_auto.sh` | The `UI_AUTO_CONFIRM` testing hook: auto-answers for dialogs. |
| `lib/utils.sh` | `checkStdin`, `withProgress`, clipboard, temp-dir helpers. |
| `lib/cli.sh` | Flag parsing and validation, `--help`, `--json` output, `requireInput` (`--no-input`), `isDryRun`. |
| `lib/integrity.sh` | Trust policy: ReShade setup checksums and shader pack commit pins. |
| `lib/reshade_pins.sh`, `lib/shader_pins.sh` | Generated pin tables. Refresh them with `scripts/release/pin-reshade.sh` and `scripts/release/pin-shader-repos.sh`, never by hand. |
| `lib/config.sh` | `init_runtime_config`: defaults, `MAIN_PATH`, and the `SHADER_REPOS` registry. |
| `lib/state.sh` | Per-game state files under `$MAIN_PATH/game-state`, repo-selection helpers. |
| `lib/shader_registry.sh` | `SHADER_REPOS` entry parsing, labels, default/first-run/requested repo selection. |
| `lib/shader_layout.sh` | Where a repo keeps its `Shaders`/`Textures` (any case, or the repo root) and whether it conflicts with what is already merged. |
| `lib/shader_build.sh` | Per-game merged shader directory: merge, link and header handling. |
| `lib/shaders.sh` | Repo clone/update (pinned commit or branch head), per-game `ReShade.ini`/preset, shader selection UI. |
| `lib/steam_detection.sh` | Steam roots and libraries, exe scoring, install-dir resolution. |
| `lib/steam_metadata.sh` | `appinfo.vdf` and PE import parsing (embedded Python), `detectSteamGames`. |
| `lib/game_selection.sh` | `getGamePath` and the manual path prompts. |
| `lib/install.sh` | Downloads and verification, DLL selection, linking into the game. |
| `lib/deps.sh` | Required-executable checks; reports all missing tools with per-manager install hints via `printErr`. |
| `lib/flow.sh` | Workspace init, ReShade version update, uninstall. |
| `lib/batch_update.sh` | `--update-all`. |
| `lib/dry_run.sh` | `--dry-run` descriptions of the install, uninstall and batch plans. Must never write a file or use the network. |
| `tests/` | `run_simple_tests.sh`, `helpers/` (fixtures, loader), `suites/` (harness, exe, detection, state, shader, shader layout, shader requirements, flow, deps, install, update, repos, ui, pe, release, release metadata, diagnostics, compile check, gui flow, cli). |
| `scripts/diagnostics/` | Smoke tests and troubleshooting helpers. |
| `docs/testing/` | Manual smoke checklists for every GUI, TUI, CLI and in-game aspect, and the GUI audit. Update them with any user-visible change. |
| `scripts/release/` | AppImage release tool. |
| `packaging/appimage/AppDir/` | AppRun, desktop entry, AppStream metainfo, icon. |
