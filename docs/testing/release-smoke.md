# Release smoke pass

The shortest pass that still catches the failures users would notice first. About 30 minutes with the
automated layer, about two hours to add the in-game checks. Copy this into the release issue.

```text
Version:            Distro / DE / session:
yad:                bash:               Steam: native | Flatpak      Proton:
```

## 1. Automated (all must pass)

- [ ] `bash tests/run_simple_tests.sh` — all tests pass
- [ ] `shellcheck $(git ls-files '*.sh')` — no output
- [ ] `bash scripts/diagnostics/smoke_cli.sh` — `SMOKE_RESULT=PASS`
- [ ] `bash scripts/diagnostics/smoke_whiptail.sh` — `SMOKE_RESULT=PASS`
- [ ] `bash scripts/diagnostics/smoke_yad.sh` — `SMOKE_RESULT=PASS` (ten scenarios)
- [ ] `scripts/release/check-version-sync.sh` — versions agree in all five places
- [ ] `scripts/release/release-appimage.sh --build-only` — AppImage builds and validates
- [ ] CI on the release commit is green (tests on Ubuntu 22.04 and 24.04, ShellCheck, packaging)

## 2. The built AppImage, on a real desktop

- [ ] LAUNCH-01 double-click starts it; the first dialog is graphical (LAUNCH-03)
- [ ] LAUNCH-02 `--version` matches the file name
- [ ] LAUNCH-21 with yad hidden, a menu launch opens a terminal instead of doing nothing
- [ ] LAUNCH-30 with `7z` hidden, the error dialog names it

## 3. The install flow, by hand, once

- [ ] INST-01 to INST-03 action list: default, arrow-key choice, cancel
- [ ] INST-10 to INST-13 game picker, including the game with `&` and `<` in its name
- [ ] INST-30 to INST-32 DLL question, No, unsupported name, valid name
- [ ] INST-40 to INST-42 shader picker: defaults, scrolling, un-tick all
- [ ] INST-50 to INST-53 progress, success dialog, failed clone and retry
- [ ] INST-60 to INST-63 completion text and the files it leaves
- [ ] INST-70 a fatal error dialog appears

## 4. Manage flows

- [ ] MANAGE-01 and MANAGE-02 uninstall removes the links and says so
- [ ] MANAGE-10 and MANAGE-11 update-all with two games, and its confirmation
- [ ] MANAGE-21 an existing `ReShade.ini` survives and gets recursive search paths

## 5. In a real game (Proton)

- [ ] SHADER-01 `compile_check.sh --packs all` passes (or the failures are understood and listed)
- [ ] SHADER-10 to SHADER-13 banner, overlay, effects from sub-folders, one effect per pack
- [ ] SHADER-20 a single small pack compiles on its own
- [ ] SHADER-30 one DX11 and one DX9 game

## 6. Publish

- [ ] `CHANGELOG.md` heading, `VERSION`, AppStream release and desktop version agree and are dated
- [ ] The GitHub release has the AppImage attached and is not a draft
- [ ] The release notes mention every item of the changelog that a user would notice
- [ ] Failed checklist items are either fixed or listed in the release notes as known issues
