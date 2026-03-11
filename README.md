# reshade-linux

> Download [ReShade](https://reshade.me/) and shaders, then link them into any Windows game running under Wine or Proton on Linux — with full GUI support, automatic Steam game detection, and zero manual configuration.

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

Or grab the self-contained **AppImage** (no dependencies needed):

```bash
chmod +x reshade-linux-x86_64.AppImage
./reshade-linux-x86_64.AppImage
```

> [!TIP]
> Install [`yad`](https://github.com/v1cont/yad) (`sudo dnf install yad` / `sudo apt install yad`) to get a full GTK GUI with game picker, progress dialogs, and folder browser. The script automatically falls back to a plain terminal UI when `yad` is absent.

---

## Features

### Game detection

| | |
|---|---|
| **Steam library scan** | Finds all Steam libraries automatically; no manual path entry needed |
| **`appinfo.vdf` parsing** | Reads Steam's binary metadata to identify the exact launch executable for every game |
| **PE import table analysis** | Inspects the Windows PE import table to pick the correct DLL override (`dxgi`, `d3d9`, `opengl32`, `ddraw`, `dinput8`, …) instead of blindly defaulting to `dxgi` |
| **Built-in directory presets** | Knows where the real executable lives for games with non-root layouts (Cyberpunk 2077, Witcher 3, Oblivion Remastered, ESO, and more) |
| **Custom directory presets** | Override any game's exe directory via `GAME_DIR_PRESETS="<AppID>\|<subdir>"` |

### Install & update workflow

| | |
|---|---|
| **Installed-game indicator** | Game picker marks already-configured games with ✔ so repeat runs are immediately obvious |
| **Per-game state files** | Installation settings (DLL, architecture, path) are saved in `~/.local/share/reshade/game-state/`; re-running a game skips the DLL dialog entirely |
| **Auto Steam launch option** | Writes the `WINEDLLOVERRIDES` launch option directly into Steam's `localconfig.vdf` — no manual copy-paste into Game Properties |
| **Batch update** (`--update-all`) | Re-links ReShade for every tracked game at once; run this after a ReShade update |

### Flatpak & GUI

| | |
|---|---|
| **Flatpak auto-detection** | Detects native vs. Flatpak Steam and sets `MAIN_PATH` accordingly; prompts if both are found |
| **GUI mode via `yad`** | Every prompt becomes a native GTK dialog when `yad` is available and a display server is present |
| **AppImage** | Self-contained build bundles `yad` so GUI mode works on systems without it installed |

### Code quality vs. upstream

| | |
|---|---|
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
./reshade-linux-x86_64.AppImage --update-all
```

State files in `~/.local/share/reshade/game-state/` record the DLL, architecture, and game path for each previously installed game. `--update-all` reads these and re-creates every symlink pointing at the latest ReShade version.

---

## AppImage

The AppImage bundles `yad` (if present on the build host) so GUI mode works on target systems without `yad` installed. GTK3 is intentionally not bundled — it is universally available on desktop Linux.

**Build requirements:** `curl`, `ImageMagick` (`magick` or `convert`). `yad` is optional.

```bash
bash appimage/build.sh
```

---

## Environment variables

All behaviour can be customised at the command line without editing the script:

```bash
VARIABLE=value ./reshade-linux.sh
```

| Variable | Default | Description |
|---|---|---|
| `MAIN_PATH` | `~/.local/share/reshade` | Where ReShade files and state are stored. Auto-detected for Flatpak Steam. |
| `UPDATE_RESHADE` | `1` | Set to `0` to skip checking for new ReShade/shader versions. |
| `RESHADE_VERSION` | `latest` | Pin to a specific ReShade version, e.g. `4.9.1`. |
| `RESHADE_ADDON_SUPPORT` | `0` | Set to `1` to use the addon-enabled build (single-player use only). |
| `SHADER_REPOS` | *(6 repos)* | Semicolon-separated list of `URI\|local-name[\|branch]` shader repositories. |
| `MERGE_SHADERS` | `1` | Merge all shader repos into a single `Merged/` folder. |
| `GAME_DIR_PRESETS` | *(empty)* | Per-game exe subdirectory overrides, e.g. `12345\|Binaries/Win64`. |
| `GLOBAL_INI` | `ReShade.ini` | Shared ReShade config linked into every game directory. |
| `LINK_PRESET` | *(empty)* | Preset `.ini` file in `MAIN_PATH` to link into every game directory. |
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
