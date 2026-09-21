# Errors and edge cases

What happens when something goes wrong or the input is unusual. A failure must be **visible** (a
dialog under the GUI, a message on the terminal), **specific** (says what and where) and **safe**
(nothing half-installed, nothing of the user's deleted).

## Paths and names

- [ ] **EDGE-01 P0** Game folder containing spaces, `&`, `'`, `"`, `$`, `(`, and non-ASCII characters: install,
  update-all and uninstall all work, and the links point at the right place.
- [ ] **EDGE-02 P0** Game named `Tom & Jerry <Demo>` in the picker and in every later dialog.
  **Auto:** `game_with_markup_characters_in_its_name`
- [ ] **EDGE-03 P1** A path typed with `~` is expanded; a relative path is made absolute; a path to an `.exe`
  file uses its folder.
- [ ] **EDGE-04 P1** A path that does not exist shows "Path does not exist:" and asks again, without leaving.
- [ ] **EDGE-05 P1** A very long path (200 characters) works and its dialog stays inside the screen.
- [ ] **EDGE-06 P2** A symlinked game folder installs into the real folder and update-all still finds it.
- [ ] **EDGE-07 P2** Non-Steam games (no App ID) are tracked by path and can be updated and uninstalled.

## Permissions and disk

- [ ] **EDGE-10 P0** A read-only game folder ends with a clear error naming the folder; nothing is left linked.
- [ ] **EDGE-11 P1** A full data disk stops with an error and does not leave a truncated ReShade download or
  a half built shader folder that the next run trusts.
- [ ] **EDGE-12 P1** An unreadable Steam library folder is skipped with a message, and other libraries are
  still listed.
- [ ] **EDGE-13 P2** A `ReShade.ini` that is not writable is not overwritten and the install says so.

## Network and downloads

- [ ] **EDGE-20 P0** A pack that cannot be cloned offers a retry and then continues without it.
  **Auto:** `failed_shader_download_offers_a_retry`
- [ ] **EDGE-21 P0** A stalled clone gives up after the low-speed timeout instead of hanging forever, and a
  credentials prompt never appears (`GIT_TERMINAL_PROMPT=0`).
- [ ] **EDGE-22 P1** A pack whose upstream history was rewritten (force push) updates cleanly without
  losing a local commit.
- [ ] **EDGE-23 P1** A repository that was renamed or moved upstream still works through the redirect.
  Known gap: an existing clone keeps its old remote address.
- [ ] **EDGE-24 P1** A wrong `RESHADE_SETUP_SHA256` stops the install; the message says the hashes differ.
- [ ] **EDGE-25 P2** Ctrl-C during a clone or download leaves no partial folder that breaks the next run.

## State and data

- [ ] **EDGE-30 P1** A corrupted or hand-edited state file (missing fields, extra lines) does not crash update-all;
  that game is skipped with a message.
- [ ] **EDGE-31 P1** A game that was deleted from Steam but is still tracked is skipped by update-all and can
  still be uninstalled by path.
- [ ] **EDGE-32 P1** Deleting `~/.local/share/reshade` while games still point at it breaks nothing worse than
  missing shaders; a new install repairs it.
- [ ] **EDGE-33 P2** Steam's `appmanifest` with unusual quoting (a name containing `"`) is read correctly.

## Environment

- [ ] **EDGE-40 P0** Started with no Steam installed at all: "Enter path manually..." works.
- [ ] **EDGE-41 P1** Started from a desktop file with a minimal `PATH`: the required programs are found or
  reported by name.
- [ ] **EDGE-42 P1** A non-UTF-8 locale (`LANG=C`) still shows readable dialogs.
- [ ] **EDGE-43 P1** Both native and Flatpak Steam present: the question is asked once, and the choice is used
  for every later step.
- [ ] **EDGE-44 P2** `set -e` in a calling script does not abort the flow half-way (the shipped scripts are
  written to be safe under it).
- [ ] **EDGE-45 P2** Headless machine (no display, no terminal): `--cli` with all options works and never opens a
  dialog.

## Security-relevant

- [ ] **EDGE-50 P0** ReShade downloads are only accepted from the official hosts; an altered download URL is
  refused.
- [ ] **EDGE-51 P0** `d3dcompiler_47.dll` is checked against its pinned hash; a different file is rejected.
- [ ] **EDGE-52 P1** A shader pack cannot make the installer run anything: packs are only cloned and their `.fx`
  and `.fxh` files linked. Check a new pack's tree for scripts or binaries before adding it.
- [ ] **EDGE-53 P1** No temporary file with predictable content is left world-writable.
