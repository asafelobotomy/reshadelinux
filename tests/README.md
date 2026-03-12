# ReShade Linux Test Suite

The supported automated test path is the shell runner in `run_simple_tests.sh`.

## Run tests

```bash
bash tests/run_simple_tests.sh
```

## Files

- `run_simple_tests.sh` - main regression suite used locally and in CI
- `fixtures.sh` - isolated temp Steam/game fixtures and shader repo helpers
- `test_functions.sh` - extracted helpers mirrored from the main script for test coverage

## Coverage

The maintained shell suite covers:

- game executable detection and filtering
- icon lookup priority
- built-in install-dir presets
- integration of the detection pipeline
- per-game state read/write behavior
- per-game shader directory rebuild behavior
- per-game `ReShade.ini` creation

## Notes

- Tests run in isolated temporary directories and do not touch the real Steam install.
- `XDG_CACHE_HOME` and `MAIN_PATH` are redirected into the temp fixture tree during tests.
- If you add new install-state or shader-selection behavior, extend `run_simple_tests.sh` and `test_functions.sh` together.

```bash
# Add to fixtures.sh
create_my_custom_game() {
    create_mock_game "My Game" "777888" \
        "game.exe" \
        "launcher.exe"
    create_mock_icon "777888"
}

# Use in tests
@test "my test" {
    create_my_custom_game
    # ... test code
}
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run tests
        run: ./tests/run_tests.sh
```

### GitLab CI

```yaml
test:
  script:
    - ./tests/run_tests.sh
  artifacts:
    reports:
      junit: test-results.xml
```

## Troubleshooting

### BATS not found
```bash
./tests/run_tests.sh --install-bats
```

### Test timeout
Tests typically complete in <1 second each. If slow:
- Check disk space
- Verify /tmp is not full
- Check CPU load

### Permission errors
Ensure scripts are executable:
```bash
chmod +x tests/*.sh
```

### Individual test fails
Run with verbose output:
```bash
bats tests/test_exe_detection.bats --verbose
```

## Future Enhancements

- [ ] Steam library discovery tests (`listSteamAppsDirs()`)
- [ ] Game picker UI tests (CLI path handling)
- [ ] Download/caching tests (CDN fallback)
- [ ] Proton/runtime filtering tests
- [ ] Performance benchmarks
- [ ] Coverage report generation (nyc/istanbul equivalent)
- [ ] Parallel test execution
- [ ] Property-based testing (generative test cases)

## License

Same as ReShade Linux wrapper (see parent LICENSE)
