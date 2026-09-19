# ReShadeLinux Test Suite

The maintained automated test path is the shell runner in `run_simple_tests.sh`.

## Run tests

```bash
bash tests/run_simple_tests.sh
```

## Files

- `run_simple_tests.sh` - main regression suite used locally and in CI
- `helpers/fixtures.sh` - isolated temp Steam, cache, and shader fixture helpers
- `helpers/test_loader.sh` - loader that sources the production libraries used by the tests
- `suites/harness_suite.sh` - self-tests proving the runner detects failing assertions and commands
- `suites/exe_suite.sh` - executable selection and scoring heuristics
- `suites/detection_suite.sh` - icon lookup, UI backend choice, presets, and Steam detection integration
- `suites/state_suite.sh` - per-game state, repo selection helpers, and shader repo entry parsing
- `suites/release_metadata_suite.sh` - `VERSION` and `CHANGELOG.md` consistency
- `suites/shader_suite.sh` - per-game shader directory construction, selection, and `ReShade.ini` generation
- `suites/flow_suite.sh` - UI helpers, dependency checks, ReShade download, and batch-update flows
- `suites/deps_suite.sh` - missing-dependency reporting: package names per manager, stderr output, and the yad error dialog
- `suites/install_suite.sh` - hash pin and download URL checks, DLL override entry, temp-dir cleanup, linking, and uninstall
- `suites/update_suite.sh` - the `latest` ReShade link across failed, interrupted, and repeated updates
- `suites/repos_suite.sh` - shader repository clone/update against real local git repositories
- `suites/ui_suite.sh` - yad plain-text dialogs and the `UI_AUTO_CONFIRM` warning
- `suites/pe_suite.sh` - PE import analysis using synthetic executables built by `create_mock_pe`
- `suites/cli_suite.sh` - CLI parsing and flow test groups sourced by the runner

## Coverage

The current shell suite covers:

- executable selection and utility filtering
- Steam icon lookup priority
- UI backend selection across YAD, terminal UI, and CLI fallback
- explicit `UI_BACKEND` override handling and validation
- built-in and custom install-directory resolution
- scan fallback for nested executable layouts when heuristic directories do not match
- per-game state read/write behavior
- installed-state verification against the actual DLL on disk
- malformed state file rejection when required keys are missing
- shader repo selection and per-game merged shader directory rebuilds
- per-game `ReShade.ini` generation
- parsing of the current `SHADER_REPOS` format with optional branch, title, and description fields
- release metadata sync between `VERSION` and the current `CHANGELOG.md` entry

## Design notes

- Tests run in isolated temporary directories and do not touch the real Steam install.
- `HOME`, `XDG_CACHE_HOME`, and `MAIN_PATH` are redirected into the fixture tree for each test.
- `helpers/test_loader.sh` should keep sourcing the production libraries directly so tests do not drift from runtime behavior.
- `suites/` contains grouped behavioral suites; `helpers/` contains setup and loader infrastructure.
- Add new test functions to the appropriate grouped test file, then invoke them from `run_simple_tests.sh`.

## CI

The repository CI runs:

```bash
bash tests/run_simple_tests.sh
```

See `.github/workflows/ci.yml` for the exact job definition.

## Adding tests

Use `helpers/fixtures.sh` to build isolated Steam libraries, icons, game directories, and shader repos. Prefer targeted regression tests that exercise one decision point at a time.

Example:

```bash
test_my_new_case() {
    local game_dir="$TEST_GAMES_DIR/MyGame"
    mkdir -p "$game_dir/bin/x64"
    touch "$game_dir/bin/x64/MyGame.exe"

    [[ "$(resolveGameInstallDir "$game_dir" "777888")" == "$game_dir/bin/x64|heuristic" ]]
}
```

## Troubleshooting

If a test fails, run the suite directly to see the failing test name:

```bash
bash tests/run_simple_tests.sh
```

If scripts lose their executable bit locally:

```bash
chmod +x tests/*.sh tests/helpers/*.sh scripts/diagnostics/*.sh
```

## License

Same as the parent project. See `LICENSE` in the repository root.
