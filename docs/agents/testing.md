# Testing rules

Moved from CLAUDE.md (the regression-test rule and the `assert_fails` rule stay there). Read before writing or changing tests or the test harness.

- Each test runs in a subshell under a real `set -e` (`_execute_test` in `run_simple_tests.sh`). Never call it from an `&&`, `||` or `if`: bash silently disables errexit there and only the last statement could fail the test. `tests/suites/harness_suite.sh` guards this.
- Register tests with `run_test "name" function`. Use `run_test_expect_fail` only for harness self-tests.
- Fixtures in `tests/helpers/fixtures.sh`: `setup_test_env`, `create_mock_game`, `create_mock_shader_repo`, `create_mock_pe` (synthetic PE with chosen imports), `assert_*`. Use real local git repositories for clone/update tests and a stubbed `PATH` for missing or fake programs (see `deps_suite.sh`).
- Tests that run flows reading runtime settings call `init_test_runtime_defaults`. To exercise a fatal path in a subshell, call `use_fatal_printErr` so `printErr` exits as it does in production.
- Stub external tools with function overrides or PATH stubs. Do not hit the network. A fake `yad` must reject what real yad rejects (see `_install_recording_yad`); a lenient stub hid a dialog that never opened.
