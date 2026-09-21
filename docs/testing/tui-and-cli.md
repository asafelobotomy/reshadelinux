# Terminal interfaces: whiptail, dialog and the plain CLI

The same flows as the GUI, on the text backends. Run with a real terminal.

**Auto:** `smoke_cli.sh` (CLI), `smoke_whiptail.sh` (whiptail, with the auto-answer hook).

## Choosing a backend

- [ ] **TUI-01 P0** From a terminal with whiptail installed, `./reshadelinux.sh` uses whiptail; without it,
  dialog; without both, plain prompts.
- [ ] **TUI-02 P0** `UI_BACKEND=<name>` and `--ui-backend=<name>` force the backend; a backend that is not
  installed stops with a clear message; an invalid name lists the allowed ones.
- [ ] **TUI-03 P1** `--cli` and `--ui-backend=...` together are rejected.
- [ ] **TUI-04 P1** `UI_BACKEND=auto` from a desktop launch without a terminal never picks whiptail or dialog.

## whiptail and dialog

- [ ] **TUI-10 P0** The action menu, game menu, DLL question, shader check list and messages appear in order and
  the install finishes with the same files as the GUI (see INST-61).
- [ ] **TUI-11 P0** Space ticks a shader pack, Tab moves between the list and the buttons, Enter confirms,
  Escape cancels with status 0 and changes nothing.
- [ ] **TUI-12 P0** `\n` in message texts is a line break, and text is not cut off in an 80x24 terminal.
- [ ] **TUI-13 P1** Resize the terminal while a dialog is open: the dialog redraws and the screen is restored
  cleanly afterwards (no leftover colours, cursor visible).
- [ ] **TUI-14 P1** The 70-pack shader list is scrollable in 80x24 and the visible rows are not cut off.
- [ ] **TUI-16 P1** Uninstall and update-all end with the summary printed in the terminal and **no** extra dialog, so a
  scripted `--update-all` in a terminal is never left waiting for a key. **Auto:** unit tests
- [ ] **TUI-15 P2** Ctrl-C at any dialog leaves the terminal usable and removes the temporary directory.

## Plain CLI

- [ ] **CLI-01 P0** `./reshadelinux.sh --cli --game-path=DIR --dll-override=dxgi --shader-repos=none` installs
  without a single question. **Auto:** `smoke_cli.sh`
- [ ] **CLI-02 P0** Interactive: `i`, then a game number or `m`, then `y` at the DLL question, works, and an
  invalid answer is asked again.
- [ ] **CLI-03 P0** `--update-all` on a machine with no tracked games exits 0 with "No installed games found",
  before it contacts the network. **Auto:** unit tests
- [ ] **CLI-04 P0** `--shader-repos=all|none|a,b` and a misspelt name (a clear "Unknown shader repository").
- [ ] **CLI-05 P1** `--list-shader-repos` prints every pack with title, creator and highlights, and exits 0.
- [ ] **CLI-06 P1** `--app-id=<id>` selects a detected game; an unknown id is a clear error.
- [ ] **CLI-07 P1** `--dll-override=winmm` is refused unless `EXTRA_DLL_OVERRIDES=winmm` is set.
- [ ] **CLI-08 P1** Closed standard input (`</dev/null`) ends with "Input closed while waiting for user
  response", not an endless loop.
- [ ] **CLI-09 P2** `--version`, `-V`, `--help` and `-h` print and exit 0 without touching the data folder.
- [ ] **CLI-10 P1** Colour is used only on a terminal: `./reshadelinux.sh --version | cat` and a redirect to a file
  contain no escape sequences, `NO_COLOR=1` turns colour off on a terminal, and `CLICOLOR_FORCE=1` turns it on
  in a pipe. **Auto:** unit tests, including a pseudo terminal
