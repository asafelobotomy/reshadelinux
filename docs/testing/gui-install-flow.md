# GUI install flow

Every dialog of an install with the yad backend, in the order a user meets them. Start with
`UI_BACKEND=yad ./reshadelinux.sh` (or `reshadelinux-gui.sh`). Use a Steam library with at least
three games, and give one game a name containing `&` and `<` (for example `Tom & Jerry <Demo>`;
a Steam `appmanifest` file is enough).

**Auto** means `scripts/diagnostics/smoke_yad.sh` already covers the item.

## 1. Action list (title "ReShade")

- [ ] **INST-01 P0** The first dialog asks "What would you like to do?" with **Install ReShade for a
  game** highlighted. **Update all installed games** is listed only once a game has been installed.
  **Auto:** `install_with_defaults`
- [ ] **INST-02 P0** Press Down, then Enter: the highlighted row is the answer (Uninstall). Clicking a
  row's text and pressing OK gives that row, not the first one.
  **Auto:** `action_list_follows_the_highlighted_row`
- [ ] **INST-03 P0** Escape, the window's close button and Cancel all end the program with status 0
  and change nothing (no state file, no linked DLL). **Auto:** `cancel_at_the_first_dialog`

## 2. Game picker (title "ReShade - Select Game")

- [ ] **INST-10 P0** Detected Steam games are listed in three columns (Game, App ID, Executable), and the
  last row is "Enter path manually...". The first row is highlighted.
- [ ] **INST-11 P0** A game named `Tom & Jerry <Demo>` shows exactly that, without `&amp;` or missing
  characters. Choosing it installs for that game. **Auto:** `game_with_markup_characters_in_its_name`
- [ ] **INST-12 P1** Double-clicking a row chooses it.
- [ ] **INST-13 P0** Escape or Cancel exits with status 0 and links nothing. **Auto:** `cancel_at_the_game_picker`
- [ ] **INST-14 P1** With no detected games the folder chooser opens straight away.
- [ ] **INST-15 P1** With 30 or more games the list scrolls and stays responsive; typing starts a search.

## 3. Manual game folder (title "ReShade - Select the game folder")

- [ ] **INST-20 P0** Choosing "Enter path manually..." opens a folder chooser that starts in
  `~/.local/share/Steam/steamapps/common` (or your home directory if that does not exist).
- [ ] **INST-21 P0** Selecting a folder that contains a `.exe` and pressing OK continues to the DLL question.
- [ ] **INST-22 P1** A folder without any `.exe` asks "No .exe file found in: … Use this folder anyway?"
  (Yes continues, No returns to the chooser).
- [ ] **INST-23 P1** Cancel ends the program with status 0.
- [ ] **INST-24 P2** A folder whose name contains spaces, `&`, `'` or non-ASCII characters is accepted
  and the installed links point at it.

## 4. DLL override (title "ReShade")

- [ ] **INST-30 P0** "Detected a 64-bit game. Use dxgi.dll as the DLL override?" (32-bit games offer
  `d3d9`) with **Yes | No**. Enter answers **Yes**. **Auto:** `install_with_defaults`
- [ ] **INST-31 P1** Choosing No opens an entry dialog pre-filled with `dxgi`.
- [ ] **INST-32 P0** Typing `winmm` shows "'winmm' is not a supported DLL override. Choose one of: …" and
  asks again. Typing `d3d11` continues, and `d3d11.dll` (not `winmm.dll`) ends up in the game folder.
  **Auto:** `unsupported_dll_name_is_rejected`
- [ ] **INST-33 P2** Cancel in the entry dialog ends the program with status 0.

## 5. Shader picker (title "ReShade - Shader Repositories")

- [ ] **INST-40 P0** The list shows every configured pack as "Title by creator | highlights"; the
  first-run defaults (Standard Effects, SweetFX, qUINT, prod80, AstrayFX) are ticked. Labels with `&`
  or `<>` render literally.
- [ ] **INST-41 P0** With the default registry (about 70 packs) the dialog scrolls, is not taller than a
  1080p screen, and no label is cut off in the middle of a word.
- [ ] **INST-42 P0** Un-ticking every pack and pressing OK continues; the summary is shown and
  `selected_repos=` in the state file is empty. **Auto:** `no_shader_packs_selected`
- [ ] **INST-43 P1** On a re-run the previous selection is ticked.
- [ ] **INST-44 P1** Selecting a pack that needs another (for example Ann-ReShade needs CShade, BFBFX
  needs ZenteonFX) also installs the required pack without showing it as ticked.
- [ ] **INST-45 P1** **Select all** (Alt+A) reopens the picker with every pack ticked and **Select none** (Alt+N) with
  none ticked; the last choice wins, OK keeps what is ticked, and Cancel leaves without installing.
  **Auto:** `shader_picker_select_all_and_none`, `shader_picker_select_none_installs_no_packs`
- [ ] **INST-46 P2** Enter in the pack list confirms with **OK** (it must not trigger Select all).

## 6. Downloading and building

- [ ] **INST-50 P0** A progress window titled "ReShade" appears while a pack is cloned ("Cloning shader
  repo:" and the address) and while the shader folder is built. The large text names the operation and
  the small text inside the bar shows the current step.
- [ ] **INST-51 P1** The progress bar keeps moving for at least ten seconds without freezing; closing
  the progress window with its close button does not stop the install and leaves no orphan process.
- [ ] **INST-52 P0** After a successful download: "Shaders have been successfully downloaded and will
  be linked to your game." with an **OK** button.
- [ ] **INST-53 P0** A pack that cannot be cloned shows "Failed to download: NAME. Retry downloading these
  repositories?" (**Yes | No**, Enter is Yes). Yes tries again; if it still fails, "Some shader
  repositories could not be downloaded. Installation will continue without them." and the install
  finishes. **Auto:** `failed_shader_download_offers_a_retry`

## 7. Result

- [ ] **INST-60 P0** "ReShade installation complete!" lists the Steam launch option (with the DLL and
  `d3dcompiler_47`), the overlay shortcut, and the shader path. The text can be selected and copied.
- [ ] **INST-61 P0** In the game folder: `dxgi.dll` (or the chosen DLL) and `d3dcompiler_47.dll` are
  links, `ReShade_shaders` is a link, and `ReShade.ini` contains `EffectSearchPaths=…\Shaders\**` and
  `TextureSearchPaths=…\Textures\**`. **Auto:** `install_with_defaults`
- [ ] **INST-62 P1** With `wl-copy`, `xclip` or `xsel` installed, "(Already copied to clipboard)" is shown
  and pasting gives the launch option.
- [ ] **INST-63 P0** A state file exists for the game with the right DLL, architecture, path, and
  selection.

## 8. Fatal errors

- [ ] **INST-70 P0** Any fatal error opens a dialog with a red icon and a **Close** button, and the
  process exits with status 1 after it is closed (for example `--app-id=999999`).
  **Auto:** `fatal_errors_are_shown_in_a_dialog`
- [ ] **INST-71 P0** A missing required program (hide `7z` from `PATH`) names it, lists every missing
  program at once, and shows the install command for your package manager.
