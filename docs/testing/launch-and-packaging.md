# Launch and packaging

How the program starts: the AppImage, the desktop entry, the wrapper, and what happens when a
required program is missing. A desktop launch has **no terminal** (`Terminal=false`), so anything
that is only printed is invisible; several items below exist for that reason.

## AppImage

- [ ] **LAUNCH-01 P0** `reshadelinux-<version>-x86_64.AppImage` is executable, starts by double-click in the
  file manager, and opens the first dialog within five seconds.
- [ ] **LAUNCH-02 P0** Run from a terminal with `--version`: prints the same version as the file name and the
  `VERSION` file. `scripts/release/check-version-sync.sh` passes.
- [ ] **LAUNCH-03 P0** With `yad` installed, the first dialog is a graphical window, not text in the terminal.
- [ ] **LAUNCH-04 P1** Two AppImages of different versions can run side by side without sharing a mount.
- [ ] **LAUNCH-05 P1** The AppImage does not write outside `~/.local/share/reshade`, the game folders you pick,
  and its temporary directory. Check with `strace -f -e trace=openat` or by comparing `find ~ -newer`.
- [ ] **LAUNCH-06 P1** Its temporary directory is gone after a normal exit, after Cancel, and after a fatal error.
- [ ] **LAUNCH-07 P2** `--help` shows every option in the README table.

## Desktop entry and metadata

- [ ] **LAUNCH-10 P0** The entry "ReShadeLinux" appears in the Games category of the menu with the ReShade icon,
  and starts the program (`Exec=reshadelinux-gui.sh`, `Terminal=false`).
- [ ] **LAUNCH-11 P1** `desktop-file-validate` and `appstreamcli validate --no-net` pass on the packaged files.
  **Auto:** the packaging job in CI.
- [ ] **LAUNCH-12 P1** The AppStream release list contains the current version with a description.
- [ ] **LAUNCH-13 P2** The window's taskbar entry shows the ReShade icon, not a generic one.

## Wrapper (`reshadelinux-gui.sh`)

- [ ] **LAUNCH-20 P0** With yad present the wrapper starts the yad backend. **Auto:** unit tests, `smoke_yad.sh`.
- [ ] **LAUNCH-21 P0** **Without yad, launched from the menu** (no terminal): a terminal window opens with the text
  interface, and stays open at the end ("Press Enter to close..."). It does not silently do nothing.
  **Auto:** unit tests with fake terminals; try it once by hand with a real emulator.
- [ ] **LAUNCH-22 P1** The same on each emulator you can install: gnome-terminal, konsole, xfce4-terminal,
  kitty, alacritty, xterm. From an AppImage, the emulator must wait (the AppImage is unmounted as soon as
  the launcher exits): the flow must finish, not fail half-way with "No such file".
- [ ] **LAUNCH-23 P1** Without yad and without any terminal emulator, a desktop notification tells you to install
  yad or run the wrapper from a terminal.
- [ ] **LAUNCH-24 P1** Started from a terminal without yad: the warning "yad is not installed; falling back to the
  default UI backend." is printed and whiptail, dialog or the plain CLI is used.
- [ ] **LAUNCH-25 P2** `RESHADELINUX_IN_TERMINAL` stops a second terminal from opening inside the first.
- [ ] **LAUNCH-26 P1** Cancelling the install, or a fatal error, inside the fallback terminal ends the program once: no second
  terminal opens, and the wrapper's exit status is the installer's, even for emulators that always exit 0 (xterm).
  **Auto:** unit tests with fake terminals; xterm was also checked for real.

## Required programs

- [ ] **LAUNCH-30 P0** With `7z` missing (rename it temporarily), choosing Install shows an error dialog naming
  `7z` and the package command for your distribution (`sudo pacman -S 7zip`, `sudo apt install p7zip-full`,
  ...), and the program exits with status 1.
- [ ] **LAUNCH-31 P0** With several tools missing, all of them are listed in one message.
- [ ] **LAUNCH-32 P1** Uninstall runs before the full program check, so a machine without `7z` can still
  uninstall. Update-all is checked like an install and needs `7z`.
- [ ] **LAUNCH-33 P1** The AppImage does not bundle these tools: the README's prerequisite list matches
  `REQUIRED_EXECUTABLES` in `lib/config.sh` (`7z curl file git grep python3 sed sha256sum`).

## First run and network

- [ ] **LAUNCH-40 P0** First run with no data folder downloads the official ReShade from reshade.me, verifies
  `d3dcompiler_47.dll` against its pinned hash, and continues into the flow.
- [ ] **LAUNCH-41 P0** With no network the error says what could not be reached and does not leave a half
  downloaded file that breaks the next run.
- [ ] **LAUNCH-42 P1** `UPDATE_RESHADE=0` does not contact reshade.me when ReShade is already present.
- [ ] **LAUNCH-43 P1** `RESHADE_SETUP_SHA256` set to a wrong value stops before extraction; a malformed value is
  reported as malformed.
- [ ] **LAUNCH-44 P2** `RESHADE_VERSION=6.7.3` installs that version and keeps a `latest` link that still works
  after a failed later update.
