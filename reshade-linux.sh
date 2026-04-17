#!/bin/bash
cat > /dev/null <<LICENSE
    Copyright (C) 2021-2022  kevinlekiller

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
    https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html
LICENSE
cat > /dev/null <<DESCRIPTION
    Bash script to download ReShade and shader repositories, then link them into a game directory
    for games using Wine or Proton on Linux. Re-running the script updates the installed files.

    Requirements:
        grep, 7z, curl, git, file, python3, sed, sha256sum
        yad : optional graphical UI when a desktop session is available
        whiptail or dialog : optional terminal UI; otherwise plain CLI prompts are used

    Notes:
        ReShade installs are stored per game. Each game gets its own shader selection state,
        merged shader directory, and local ReShade.ini.

        Re-running the script for an already installed game lets you change the selected shader
        repositories for that game. Unticking a repo removes its shaders from that game's merged
        ReShade shader directory.

    Usage:
        chmod u+x reshade-linux.sh
        ./reshade-linux.sh
        ./reshade-linux.sh --update-all
DESCRIPTION

SCRIPT_DIR="$(dirname "$(realpath -- "$0")")"

. "$SCRIPT_DIR/lib/logging.sh" || { printf 'Failed to source %s\n' "$SCRIPT_DIR/lib/logging.sh" >&2; exit 1; }
. "$SCRIPT_DIR/lib/ui.sh" || { printf 'Failed to source %s\n' "$SCRIPT_DIR/lib/ui.sh" >&2; exit 1; }
. "$SCRIPT_DIR/lib/utils.sh" || { printf 'Failed to source %s\n' "$SCRIPT_DIR/lib/utils.sh" >&2; exit 1; }
. "$SCRIPT_DIR/lib/cli.sh" || { printf 'Failed to source %s\n' "$SCRIPT_DIR/lib/cli.sh" >&2; exit 1; }
. "$SCRIPT_DIR/lib/config.sh" || { printf 'Failed to source %s\n' "$SCRIPT_DIR/lib/config.sh" >&2; exit 1; }
. "$SCRIPT_DIR/lib/state.sh" || { printf 'Failed to source %s\n' "$SCRIPT_DIR/lib/state.sh" >&2; exit 1; }
. "$SCRIPT_DIR/lib/shaders.sh" || { printf 'Failed to source %s\n' "$SCRIPT_DIR/lib/shaders.sh" >&2; exit 1; }
. "$SCRIPT_DIR/lib/steam_detection.sh" || { printf 'Failed to source %s\n' "$SCRIPT_DIR/lib/steam_detection.sh" >&2; exit 1; }
. "$SCRIPT_DIR/lib/steam_metadata.sh" || { printf 'Failed to source %s\n' "$SCRIPT_DIR/lib/steam_metadata.sh" >&2; exit 1; }
. "$SCRIPT_DIR/lib/game_selection.sh" || { printf 'Failed to source %s\n' "$SCRIPT_DIR/lib/game_selection.sh" >&2; exit 1; }
. "$SCRIPT_DIR/lib/install.sh" || { printf 'Failed to source %s\n' "$SCRIPT_DIR/lib/install.sh" >&2; exit 1; }
. "$SCRIPT_DIR/lib/flow.sh" || { printf 'Failed to source %s\n' "$SCRIPT_DIR/lib/flow.sh" >&2; exit 1; }

SEPARATOR="------------------------------------------------------------------------------------------------"
# Read version from co-located VERSION file; fall back to hard-coded string for
# users who download just the .sh without the rest of the repository.
# shellcheck disable=SC2034  # Consumed by flow helpers sourced from lib/flow.sh.
SCRIPT_VERSION="$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || printf '1.3.1')"
parseCliArgs "$@"
init_runtime_config
validateCliArgs
handleCliInfoArgs

checkRequiredExecutablesForMode selection

# Z0000 Create MAIN_PATH
# Z0005 Check if update enabled.
# Z0010 Download / update shaders.
# Z0015 Download / update latest ReShade version.
# Z0016 Download version of ReShade specified by user.
# Z0020 Process GLOBAL_INI.
# Z0030 DirectX / OpenGL uninstall.
# Z0035 DirectX / OpenGL find correct ReShade DLL.
# Z0040 Download d3dcompiler_47.dll.
# Z0045 DirectX / OpenGL link files to game directory.

initializeMainWorkspace
printInstallerBanner

# Z0030
maybeHandleDirectXUninstall
# Z0030

checkRequiredExecutablesForMode install
printShaderUpdateStatus
ensureRequestedReshadeVersion

# Z0028 Batch update: re-link ReShade for all previously installed games.
maybeHandleBatchUpdate

# Z0035
selectInstallGameTarget
resolveInstallDllSelection
# Z0035

# Z0037 Shader selection — let the user pick which repos to link for this game.
resolveInstallShaderSelection
# Z0037

# If WINEPREFIX was not set by the user or Vulkan path, try to auto-detect it
# from the game path when the game lives under a Steam steamapps/common/ tree.
autoDetectWineprefixFromGamePath

# Z0040
withProgress "Downloading d3dcompiler_47.dll ($exeArch-bit)..." \
    downloadD3dcompiler_47 "$exeArch"
linkD3dcompilerToWineprefix "$exeArch"
# Z0040

# Z0045
if [[ $_shaderDownloadSuccess -eq 0 && -n $_selectedRepos ]]; then
    printf '%bWarning: one or more shader repositories could not be downloaded. Linking will proceed with available repos only.%b\n' "$_YLW" "$_R"
fi
withProgress "Building and linking ReShade shaders to game directory..." linkGameFilesForInstall
# Z0045

# Persist installation details so future runs can skip the DLL dialog
# and the batch --update-all mode knows which games have ReShade.
writeGameState "$_selectedGameKey" "$gamePath" "$wantedDll" "$exeArch" "$_selectedRepos" "$_selectedAppId"

gameEnvVar="WINEDLLOVERRIDES=\"d3dcompiler_47=n;$wantedDll=n,b\""

_clipCopied=0
if [[ -n $_selectedAppId ]] && copyToClipboard "$gameEnvVar %command%"; then
    _clipCopied=1
    printf '%bSteam launch option copied to clipboard.%b Paste it into Game Properties -> Launch Options.\n' \
        "$_GRN" "$_R"
fi

printf '%b%s\n  Done!\n%s%b\n' "$_GRN$_B" "$SEPARATOR" "$SEPARATOR" "$_R"

# Print configuration summary (Steam launcher command and first-run setup)
printf '\n%bSteam launch option required for Steam launches%b (Game Properties -> Launch Options):\n  %b%s %%command%%%b\n' \
    "$_GRN$_B" "$_R" "$_CYN$_B" "$gameEnvVar" "$_R"
if [[ $_clipCopied -eq 1 ]]; then
    printf '%b(Copied to clipboard)%b\n' "$_GRN" "$_R"
fi
printf '%bNon-Steam — run the game with:%b\n  %b%s%b\n' \
    "$_GRN$_B" "$_R" "$_CYN$_B" "$gameEnvVar" "$_R"
printf '\n%bReShade first-run setup:%b\n' "$_GRN$_B" "$_R"
printf '  In the ReShade overlay, open the %bSettings%b tab.\n' "$_B" "$_R"
printf '  Shader paths have been written to ReShade.ini pointing inside: %b%s/ReShade_shaders/Merged/%b\n' \
    "$_CYN" "$gamePath" "$_R"
printf '  If an existing ReShade.ini was already present it was preserved — verify paths in Settings if shaders do not load.\n'
printf '  Then go to the %bHome%b tab and click %bReload%b.\n' "$_B" "$_R" "$_B" "$_R"
if [[ -z $WINEPREFIX ]]; then
    printf '\n%bNote:%b ReShade 6.5+ also requires d3dcompiler_47.dll inside the game'"'"'s Wine/Proton prefix.\n' "$_YLW$_B" "$_R"
    printf '  If shaders fail to compile, re-run the script with:\n'
    printf '  %bWINEPREFIX="%s/.local/share/Steam/steamapps/compatdata/<AppID>/pfx" %s%b\n' \
        "$_CYN" "$HOME" "$0" "$_R"
fi
if [[ $_UI_BACKEND != cli ]]; then
    _summary="ReShade installation complete!\n\nNext steps:\n\n1. Configure Steam launch option in Game Properties:\n$gameEnvVar %command%"
    if [[ $_clipCopied -eq 1 ]]; then
        _summary+="\n\n(Already copied to clipboard)"
    fi
    _summary+="\n\n2. Open the ReShade overlay in-game (usually Ctrl+Shift+Backspace)\n\n3. Shader paths are pre-configured in ReShade.ini to:\n$gamePath/ReShade_shaders/Merged/\n   If an existing ReShade.ini was preserved, verify paths in the Settings tab.\n\n4. Click Home tab and Reload"
    ui_msgbox "ReShade - Installation Complete" "$_summary" 18 78
fi
