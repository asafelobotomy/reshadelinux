# Smoke checklists

Manual and automated checks for every part of ReShadeLinux that a user can see or touch. The
checklists exist because a stubbed `yad` in the unit tests cannot tell whether a dialog really
opens: the 2026-09 audit found message boxes that never appeared on current yad, and a radio list
that returned the wrong answer (see [audit-2026-09.md](audit-2026-09.md)). Only a real dialog on a
real display shows that.

## How to use them

1. Run the automated layer first. Everything it covers is marked **Auto** in the checklists and
   can be skipped by hand.
2. Pick the checklists for what changed (table below) or, before a release, work through
   [release-smoke.md](release-smoke.md) plus every item tagged **P0**.
3. Test on at least one X11 and one Wayland session, and record the environment (below).
4. Copy the checklist into the pull request or release issue and tick items as you go. A failed
   item gets a short note: what happened, the log path, and the environment.

## Automated layer

| Command | Covers | Needs |
| --- | --- | --- |
| `bash tests/run_simple_tests.sh` | Logic, dialog arguments against a strict fake `yad`, wrappers, packaging metadata | bash, git, python3 |
| `bash scripts/diagnostics/smoke_cli.sh` | Full CLI installs, autodetect, shader retry, `--update-all` | 7z |
| `bash scripts/diagnostics/smoke_whiptail.sh` | Full install on the whiptail backend | whiptail, 7z |
| `bash scripts/diagnostics/smoke_yad.sh` | Ten real-yad scenarios on a private X server (see below) | yad, Xvfb, xdotool |
| `bash scripts/diagnostics/compile_check.sh --packs NAME` | Real ReShade under GE-Proton compiles the merged effects | network, about 4 GB, a display |

`smoke_yad.sh` never touches your desktop: it starts its own X server, drives real dialogs with
keystrokes, and checks the files each flow leaves behind. Set `SMOKE_YAD_SHOTS=DIR` to keep a
screenshot of every dialog, which is the quickest way to review how the dialogs look.

## Checklists

| File | Area | Run when |
| --- | --- | --- |
| [launch-and-packaging.md](launch-and-packaging.md) | AppImage, desktop entry, wrapper, missing programs | Packaging, wrapper or dependency changes |
| [gui-install-flow.md](gui-install-flow.md) | Every dialog of an install, in order | Any change under `lib/` |
| [gui-manage-flows.md](gui-manage-flows.md) | Uninstall, update-all, reinstall, several games | Flow or state changes |
| [dialog-behaviour.md](dialog-behaviour.md) | Keyboard, mouse, sizing, text rendering, themes | `lib/ui.sh` changes |
| [tui-and-cli.md](tui-and-cli.md) | whiptail, dialog, plain CLI, flags | CLI or backend changes |
| [shader-packs-in-game.md](shader-packs-in-game.md) | Shaders actually loading and compiling in a Proton game | Registry or merge changes |
| [errors-and-edge-cases.md](errors-and-edge-cases.md) | Failures, odd paths, hostile input | Any release |
| [release-smoke.md](release-smoke.md) | Short pre-release pass over all of the above | Every release |

## Item format

`- [ ] **ID** steps → expected result.` followed by **Auto:** when a test already covers it.
Priority tags: **P0** must pass to ship, **P1** should pass, **P2** polish.

## Recording the environment

Write this at the top of every filled-in checklist:

```text
Version:        (VERSION file, or the AppImage file name)
Distro / DE:    (for example Arch, KDE Plasma 6, Wayland)
yad version:    (yad --version)   bash: (bash --version | head -1)
Steam:          native | Flatpak | none        Proton:  (GE-Proton11-7, Proton 10 ...)
GPU / driver:   (for example Intel Mesa 25.2, NVIDIA 580)
```

## Reference environments

At least these should be covered over a release cycle, because they behave differently:

- **yad 0.40** (Ubuntu 22.04 and 24.04) and **yad 14 or newer** (Arch, Fedora). Newer yad rejects
  options that older releases accepted, and the reverse.
- **bash 5.1** (Ubuntu 22.04) and **bash 5.2 or newer**.
- **X11 and Wayland.** GTK dialogs open through XWayland or natively, and window placement and
  focus differ.
- **Native Steam and Flatpak Steam.** With both present the tool asks which one to use.
