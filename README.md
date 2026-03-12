# reshade-linux

> Download [ReShade](https://reshade.me/) and shaders, then link them into any Windows game running under Wine or Proton on Linux — with a terminal UI, automatic Steam game detection, and per-game configuration.

> [!NOTE]
> This is an independent continuation of [kevinlekiller/reshade-steam-proton](https://github.com/kevinlekiller/reshade-steam-proton). All original work and credit belongs to [kevinlekiller](https://github.com/kevinlekiller). This fork modernises the codebase, fixes active bugs, and adds substantial new features.

---

## Quick start

```bash
# Download
curl -LO https://github.com/asafelobotomy/reshade-steam-proton/raw/main/reshade-linux.sh

# Run
chmod u+x reshade-linux.sh && ./reshade-linux.sh
```

> [!TIP]
> Install `whiptail` or `dialog` to get a full-screen terminal UI. If neither is available, the script falls back to plain interactive CLI prompts.

---

## Features

### Game detection

| | |
| --- | --- |
| **Steam library scan** | Finds all Steam libraries automatically; no manual path entry needed |
| **`appinfo.vdf` parsing** | Reads Steam's binary metadata to identify the exact launch executable for every game |
| **PE import table analysis** | Inspects the Windows PE import table to pick the correct DLL override (`dxgi`, `d3d9`, `opengl32`, `ddraw`, `dinput8`, …) instead of blindly defaulting to `dxgi` |
| **Built-in directory presets** | Knows where the real executable lives for games with non-root layouts (Cyberpunk 2077, Witcher 3, Oblivion Remastered, ESO, and more) |
| **Custom directory presets** | Override any game's exe directory via `GAME_DIR_PRESETS="<AppID>\|<subdir>"` |

### Install & update workflow

| | |
| --- | --- |
| **Installed-game indicator** | Game picker marks already-configured games with ✔ so repeat runs are immediately obvious |
| **Per-game state files** | Installation settings are saved per game in `~/.local/share/reshade/game-state/`, including non-Steam installs keyed by path; re-running a game skips the DLL dialog entirely |
| **Per-game config** | Every install gets its own `ReShade.ini` and `ReShade_shaders/` link inside the game directory; no shared global ReShade config is linked across games |
| **Steam launch option output** | Prints the required `WINEDLLOVERRIDES` launch option for Steam and copies it to the clipboard when supported, so it can be pasted into Game Properties |
| **Batch update** (`--update-all`) | Re-links ReShade for every tracked game at once; run this after a ReShade update |

### Flatpak & interface

| | |
| --- | --- |
| **Flatpak auto-detection** | Detects native vs. Flatpak Steam and sets `MAIN_PATH` accordingly; prompts if both are found |
| **Terminal UI** | Uses `whiptail` first, then `dialog`, and falls back to plain CLI if neither is installed |

### Code quality vs. upstream

| | |
| --- | --- |
| **Security** | Removed unsafe `eval`; tilde expansion handled with `${var/#\~/$HOME}`; `curl --fail` throughout |
| **Correctness** | `ls` replaced with `[[ -d ]]`/`compgen -G`; indirect `$?` checks eliminated (ShellCheck SC2181) |
| **Performance** | Shader repo loop rewritten to remove 4+ subshells per iteration; pure-Bash path construction |
| **HTTPS** | `RESHADE_URL_ALT` upgraded from `http://` to `https://` |
| **D3D12** | `d3d12` added to `COMMON_OVERRIDES` (ReShade officially supports Direct3D 12) |
| **Shader repos** | Replaced stale `martymcmodding/qUINT` with its active successor [`iMMERSE`](https://github.com/martymcmodding/iMMERSE); added [`fubax-shaders`](https://github.com/Fubaxiusz/fubax-shaders) |
| **D3D compiler** | `downloadD3dcompiler_47()` uses [mozilla/fxc2](https://github.com/mozilla/fxc2) (same as Winetricks) with sha256 verification instead of a 50 MB Firefox 62 installer |
| **ShellCheck** | Zero warnings |

---

## Batch update

After downloading a new version of ReShade, re-link all tracked games without any prompts:

```bash
./reshade-linux.sh --update-all
```

State files in `~/.local/share/reshade/game-state/` record the DLL, architecture, game path, and selected shader repos for each previously installed game. `--update-all` reads these and re-creates each game's own `ReShade_shaders/` link and per-game config.

---

## Environment variables

All behaviour can be customised at the command line without editing the script:

```bash
VARIABLE=value ./reshade-linux.sh
```

| Variable | Default | Description |
| --- | --- | --- |
| `MAIN_PATH` | `~/.local/share/reshade` | Where ReShade files and state are stored. Auto-detected for Flatpak Steam. |
| `UPDATE_RESHADE` | `1` | Set to `0` to skip checking for new ReShade/shader versions. |
| `RESHADE_VERSION` | `latest` | Pin to a specific ReShade version, e.g. `4.9.1`. |
| `RESHADE_ADDON_SUPPORT` | `0` | Set to `1` to use the addon-enabled build (single-player use only). |
| `SHADER_REPOS` | *(6 repos)* | Semicolon-separated list of `URI\|local-name[\|branch]` shader repositories. |
| `GAME_DIR_PRESETS` | *(empty)* | Per-game exe subdirectory overrides, e.g. `12345\|Binaries/Win64`. |
| `GLOBAL_INI` | `ReShade.ini` | Template used to create a per-game `ReShade.ini` if the game does not already have one. Set to `0` to let ReShade create it on first launch. |
| `LINK_PRESET` | *(empty)* | Preset `.ini` file in `MAIN_PATH` to copy into a game's directory on first install. |
| `WINEPREFIX` | *(auto)* | Force a specific Wine prefix; auto-detected from `compatdata/` otherwise. |
| `DELETE_RESHADE_FILES` | `0` | Also delete `ReShade.log` and `ReShadePreset.ini` when uninstalling. |
| `FORCE_RESHADE_UPDATE_CHECK` | `0` | Bypass the 4-hour update check throttle. |
| `VULKAN_SUPPORT` | `0` | Enable the experimental Vulkan registry path (currently non-functional). |

For full documentation of every variable and flag, see the [comments at the top of the script](https://github.com/asafelobotomy/reshade-steam-proton/blob/main/reshade-linux.sh#L21).

---

## Alternatives

For native Vulkan games, or Windows games running through DXVK/VKD3D, consider:

- **[vkBasalt](https://github.com/DadSchoorse/vkBasalt)** — post-processing layer for Vulkan; works with native Linux games, DXVK (D3D9–D3D11), and VKD3D (D3D12)
- **vkBasalt via [Gamescope](https://github.com/Plagman/gamescope/)** — run vkBasalt on the compositor instead of the game, which works for any game Gamescope wraps
