# reshade-linux

Bash script to download [ReShade](https://reshade.me/) and shaders and link them to games running with Wine or Proton on Linux.

> **Attribution:** This repository is an independent continuation of [kevinlekiller/reshade-steam-proton](https://github.com/kevinlekiller/reshade-steam-proton), originally written by [kevinlekiller](https://github.com/kevinlekiller). All original work and credit belongs to them. This fork modernises the codebase, fixes active bugs, and is maintained independently.

## Improvements over the original

- `downloadD3dcompiler_47()`: replaced Firefox 62 CDN (~50 MB installer) with a direct download from [mozilla/fxc2](https://github.com/mozilla/fxc2) — the same source used by Winetricks — with sha256 integrity verification.
- `d3d12` added to `COMMON_OVERRIDES` (ReShade officially supports Direct3D 12).
- Removed unsafe `eval` usage; tilde expansion handled safely with `${var/#\~/$HOME}`.
- `ls` replaced with `[[ -d ]]` and `compgen -G` for directory and glob tests.
- Shader repo loop rewritten to eliminate 4+ subshells per iteration.
- `which` replaced with `command -v`; `echo -ne` replaced with `printf`.
- `WINE_MAIN_PATH` and `LINKS` construction converted to pure Bash (no subshells).
- `cat` replaced with `$(< file)` for reading version files.
- `curl --fail` added to prevent silent HTTP error pages being treated as success.
- All `[[ $? ]]` indirect exit-code checks replaced with direct checks (ShellCheck SC2181).
- `RESHADE_URL_ALT` upgraded from `http://` to `https://`.
- `SHADER_REPOS` updated: replaced `martymcmodding/qUINT` (3 years stale) with its active successor [`martymcmodding/iMMERSE`](https://github.com/martymcmodding/iMMERSE); added [`Fubaxiusz/fubax-shaders`](https://github.com/Fubaxiusz/fubax-shaders), which is featured in the official ReShade installer.
- Flatpak Steam auto-detection: the script detects whether Steam is installed natively or as a Flatpak and sets `MAIN_PATH` automatically. If both are present it prompts the user to choose. The separate `reshade-linux-flatpak.sh` wrapper is no longer needed.
- Zero ShellCheck warnings.

## Usage

### Quick:

Download the script:

    curl -LO https://github.com/asafelobotomy/reshade-steam-proton/raw/main/reshade-linux.sh

Make it executable:

    chmod u+x reshade-linux.sh

Execute the script:

    ./reshade-linux.sh

### Detailed:

For full usage instructions, see the comments at the top of the script:

https://github.com/asafelobotomy/reshade-steam-proton/blob/main/reshade-linux.sh#L21

## Alternatives

### vkBasalt:
https://github.com/DadSchoorse/vkBasalt

For native Linux Vulkan games, Windows games which can run through DXVK (D3D9 / D3D10 / D3D11) and Windows games which can run through VKD3D (D3D12).

### vkBasalt through Gamescope:

Since [gamescope](https://github.com/Plagman/gamescope/) can use Vulkan, you can run vkBasalt on gamescope itself, instead of on the game.

## Misc

`reshade-linux.sh` is the main script — works with any Windows game running under Wine or Proton. It auto-detects whether Steam is installed natively or as a Flatpak and configures `MAIN_PATH` accordingly.
