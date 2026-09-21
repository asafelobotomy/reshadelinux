# Dialog behaviour

How the dialogs behave, independent of the flow. Run on X11 and Wayland, on the desktop
environments you support, and with each yad version you ship for.

## Message, question and error dialogs

- [ ] **DLG-01 P0** A message dialog shows an icon, the text, and one **OK** button; Enter closes it.
  **Auto:** `install_with_defaults`
- [ ] **DLG-02 P0** A question shows **Yes | No**. Enter answers Yes, Tab then Enter answers No, and Escape
  or the window's close button answers No.
- [ ] **DLG-03 P0** An error dialog has a red icon and a **Close** button.
  **Auto:** `fatal_errors_are_shown_in_a_dialog`
- [ ] **DLG-04 P0** Line breaks written as `\n` in the source appear as real line breaks, and a blank line
  between paragraphs is kept.
- [ ] **DLG-05 P0** Text is shown literally: `&`, `<`, `>` and `%` in game names and paths are not
  interpreted as markup. Test with `Tom & Jerry <Demo>` and a path containing `&amp;`.
- [ ] **DLG-07 P1** Messages that report a problem (path does not exist, unsupported DLL name, packs that could not
  be downloaded) show a **warning** icon; plain information and results show the information icon.
  **Auto:** unit tests for the dialog options
- [ ] **DLG-06 P2** A very long line (a 200-character path) wraps or scrolls without making the window wider
  than the screen.

## Lists

- [ ] **DLG-10 P0** In every single-choice list the highlighted row is the answer; pressing OK, Enter or
  double-clicking returns that row. There are no radio buttons that can disagree with the highlight.
- [ ] **DLG-11 P0** The default choice is highlighted when the dialog opens.
- [ ] **DLG-12 P0** In the shader list, ticking is done with the check box (or Space on the row); OK
  returns exactly the ticked packs, in any order the list shows them.
- [ ] **DLG-13 P1** Labels containing `&`, `<` and `>` render literally in menu, list and check list rows.
- [ ] **DLG-14 P1** Column headers are readable and no hidden "Key" column is visible.
- [ ] **DLG-15 P2** Typing in a list jumps to or filters matching rows (yad's interactive search).

## Entry and folder dialogs

- [ ] **DLG-20 P0** The entry dialog opens with its default text selected, so typing replaces it.
  **Auto:** `unsupported_dll_name_is_rejected`
- [ ] **DLG-21 P0** The folder chooser returns the folder you selected, not its parent.
- [ ] **DLG-22 P1** Cancel and Escape in any input dialog return to the caller without an error message.

## Progress dialog

- [ ] **DLG-30 P0** The progress window opens for long steps and closes by itself when they finish, without
  a flash of an empty window for instant steps.
- [ ] **DLG-31 P1** Step text changes are visible; text containing `<` or `&` is not mangled.
- [ ] **DLG-32 P1** With `PROGRESS_UI=0` no progress window appears and the flow is unchanged.

## Windows, focus and sizing

- [ ] **DLG-40 P0** Every dialog appears on the current screen and workspace, in front, with keyboard focus
  (Enter works without clicking first).
- [ ] **DLG-41 P0** Dialog titles are the ones listed in [gui-install-flow.md](gui-install-flow.md), so
  the taskbar entries are recognisable.
- [ ] **DLG-42 P1** Dialogs open fully on a 1366x768 screen and on a 4K screen with 200% scaling.
- [ ] **DLG-43 P1** Dark and light themes are both legible (icons, selection colours, disabled text).
- [ ] **DLG-44 P1** Two monitors: dialogs open on the monitor with the mouse or the launching window.
- [ ] **DLG-45 P2** Resizing a list dialog keeps the buttons visible.
- [ ] **DLG-46 P2** A dialog does not steal focus from a game running in the foreground while a background
  update runs.

## Backends and fallbacks

- [ ] **DLG-50 P0** With `yad` installed and a display, `reshadelinux-gui.sh` always uses yad, even when
  started from a terminal.
- [ ] **DLG-51 P1** `UI_BACKEND=yad` without yad installed stops with "Requested UI backend 'yad' is not
  installed", not a silent exit.
- [ ] **DLG-52 P1** A yad that answers "Unknown option" (an older or newer release) is visible in the
  debug log (`RESHADE_DEBUG_LOG=/tmp/reshade.log`) instead of looking like the user pressed Cancel.
- [ ] **DLG-53 P1** With `UI_AUTO_CONFIRM=1` a warning about the testing hook is printed and every dialog
  answers itself; without it, nothing is answered automatically.
