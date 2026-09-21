# GUI manage flows

Uninstall, update-all, reinstall and several games. Run these after
[gui-install-flow.md](gui-install-flow.md) has left at least one installed game.

## Uninstall (action list, "Uninstall ReShade for a game")

- [ ] **MANAGE-01 P0** Choosing Uninstall and then a game removes the DLL link, `d3dcompiler_47.dll` link
  and `ReShade_shaders` link from that game folder, deletes its state file and merged shader folder,
  and leaves the game's own files and `ReShade.ini` alone. **Auto:** `action_list_follows_the_highlighted_row`
- [ ] **MANAGE-02 P0** On the yad backend, a dialog "ReShade - Uninstall Complete" names the folder and reminds you to remove
  the `WINEDLLOVERRIDES` launch option. (Earlier versions only printed this to a terminal, which a desktop launch
  does not have.)
- [ ] **MANAGE-03 P1** Cancelling at the game picker leaves everything installed.
- [ ] **MANAGE-04 P1** Uninstalling a game that was never installed finishes without an error and without
  deleting anything.
- [ ] **MANAGE-05 P1** After an uninstall the game still starts normally with its launch options cleared.

## Update all (action list, "Update all installed games")

- [ ] **MANAGE-10 P0** With two installed games, update-all relinks both to the latest ReShade and rebuilds
  their shader folders; each game keeps its own DLL, architecture and shader selection.
- [ ] **MANAGE-11 P0** On the yad backend, "ReShade - Update Complete" says how many games were updated and how many skipped.
  **Auto:** `update_all_ends_with_a_confirmation`
- [ ] **MANAGE-12 P1** A game whose folder was moved or deleted is skipped and counted, and the dialog
  explains what to do. The other games are still updated.
- [ ] **MANAGE-13 P1** The option is absent from the action list when nothing is installed.
- [ ] **MANAGE-14 P1** A pack that cannot be updated keeps its previous clone and the game still gets a
  shader folder.
- [ ] **MANAGE-15 P2** Update-all does not ask any question apart from the action list.

## Reinstall and changes

- [ ] **MANAGE-20 P0** Installing again for an installed game and changing the shader selection rebuilds
  the merged folder with exactly the new selection, and the state file shows it.
- [ ] **MANAGE-21 P0** An existing `ReShade.ini` is kept (your presets and settings survive); its old
  non-recursive search paths are corrected to end in `\**`, and custom search path lists are left alone.
- [ ] **MANAGE-22 P0** A real `ReShade_shaders` folder in the game directory (a manual install) is moved
  aside to `ReShade_shaders.bak-<timestamp>`, never deleted.
- [ ] **MANAGE-23 P1** Installing over a game that still has a `dxgi.dll` from another tool asks or
  replaces only a link, never a real file.
- [ ] **MANAGE-24 P1** Switching the DLL (dxgi to d3d11) leaves no stale `dxgi.dll` link behind.

## Several games and libraries

- [ ] **MANAGE-30 P1** Two games installed with different selections keep independent merged folders
  under `game-shaders/<key>`.
- [ ] **MANAGE-31 P1** A game in a second Steam library folder is detected and installs correctly.
- [ ] **MANAGE-32 P1** Native and Flatpak Steam both present: the first dialog asks which to target and the
  answer decides where data is stored.
- [ ] **MANAGE-33 P2** Running two instances at once does not corrupt a state file.
