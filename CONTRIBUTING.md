# Contributing

Thanks for helping. This is a Bash project (`bash` 5.x on Linux), so the checks below need nothing beyond `bash`, `git`, `python3`, `curl`, `file`, `grep`, `sed` and `sha256sum`, plus [ShellCheck](https://www.shellcheck.net/) for linting.

## Run the checks

```bash
bash tests/run_simple_tests.sh          # the whole suite; must pass
shellcheck $(git ls-files '*.sh')       # must print nothing
```

The suite runs every test in an isolated temporary `HOME`, so it never touches your real Steam library or ReShade data. CI runs both commands on Ubuntu 22.04 (bash 5.1) and 24.04 (bash 5.2).

## Making a change

1. Write the test first and watch it fail for the reason you expect, then make the change. Tests live in `tests/suites/`; see `tests/README.md` for the helpers.
2. Keep files under 400 lines (a warning starts at 250). Split a module before extending one that is over the limit.
3. Run both checks above. Update `README.md` and `CHANGELOG.md` for anything a user would notice.
4. Use [Conventional Commits](https://www.conventionalcommits.org/) for messages: `fix:`, `feat:`, `test:`, `refactor:`, `docs:`, `chore:`.

Things that catch people out, and are worth knowing before you start:

- **`set -e` is off in the shipped scripts** and on in the tests. Write code that behaves either way: no bare `(( n++ ))`, and `var=$(cmd) || var=""` when "not found" is normal.
- **Tests need real assertions.** Use `assert_fails cmd` to expect a failure, never a bare `! cmd`; bash exempts negated commands from `set -e`, so the test would pass anyway. A test in the suite checks for this.
- **`printErr` ends the process.** In tests, call `use_fatal_printErr` inside a subshell to get the same behaviour.
- **All dialogs go through the `ui_*` helpers**, so the yad, whiptail, dialog and plain CLI paths stay in step.
- **Tests must not use the network.** Use a stubbed `PATH`, function overrides or a local bare git repository (see `tests/suites/repos_suite.sh`).

## Adding a shader repository

Add an entry to `SHADER_REPOS` in `lib/config.sh` in the format `URL|local-name[|branch[|title[|description]]]`, then check it with the audit script, which clones it and verifies layout discovery and the merged output:

```bash
SHADER_REPOS='https://github.com/OWNER/REPO|my-shaders||Title|What it does' \
    bash scripts/diagnostics/audit_shaders.sh
```

The registry test rejects malformed or duplicate entries. The official package list is `EffectPackages.ini` on the `list` branch of `crosire/reshade-shaders`.

## Releasing

Maintainers build and validate an AppImage without side effects using `scripts/release/release-appimage.sh --build-only`. A real release starts from `main` with only the version files changed; see `scripts/README.md` and `packaging/README.md`.

## Reporting security problems

Please use the private route in [SECURITY.md](SECURITY.md) rather than a public issue.
