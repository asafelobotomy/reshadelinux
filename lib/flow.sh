# shellcheck shell=bash
# shellcheck disable=SC2154

function checkRequiredExecutables() {
    local REQUIRED_EXECUTABLE _pkg

    for REQUIRED_EXECUTABLE in "${REQUIRED_EXECUTABLES[@]}"; do
        if ! command -v "$REQUIRED_EXECUTABLE" &>/dev/null; then
            printf "Program '%s' is missing, but it is required.\n" "$REQUIRED_EXECUTABLE"
            case "$REQUIRED_EXECUTABLE" in
                7z)   _pkg="p7zip-full" ;;
                curl) _pkg="curl" ;;
                file) _pkg="file" ;;
                git)  _pkg="git" ;;
                grep) _pkg="grep" ;;
                sed)  _pkg="sed" ;;
                sha256sum) _pkg="coreutils" ;;
                *) _pkg="$REQUIRED_EXECUTABLE" ;;
            esac
            if command -v apt-get &>/dev/null; then
                printf '  Install with:  sudo apt-get install %s\n' "$_pkg"
            elif command -v dnf &>/dev/null; then
                printf '  Install with:  sudo dnf install %s\n' "$_pkg"
            elif command -v pacman &>/dev/null; then
                printf '  Install with:  sudo pacman -S %s\n' "$_pkg"
            elif command -v zypper &>/dev/null; then
                printf '  Install with:  sudo zypper install %s\n' "$_pkg"
            fi
            printf 'Exiting.\n'
            exit 1
        fi
    done
}

function initializeMainWorkspace() {
    local _ago

    mkdir -p "$MAIN_PATH" || printErr "Unable to create directory '$MAIN_PATH'."
    cd "$MAIN_PATH" || exit

    mkdir -p "$RESHADE_PATH"
    mkdir -p "$MAIN_PATH/ReShade_shaders"
    mkdir -p "$MAIN_PATH/External_shaders"

    LASTUPDATED=0
    [[ -f LASTUPDATED ]] && LASTUPDATED=$(< LASTUPDATED)
    [[ ! $LASTUPDATED =~ ^[0-9]+$ ]] && LASTUPDATED=0
    if [[ $LASTUPDATED -gt 0 && $(($(date +%s) - LASTUPDATED)) -lt 14400 ]]; then
        UPDATE_RESHADE=0
        _ago=$(( ($(date +%s) - LASTUPDATED) / 60 ))
        printf '%bSkipping update check (last checked %d min ago). Set FORCE_RESHADE_UPDATE_CHECK=1 to override.%b\n\n' \
            "$_YLW" "$_ago" "$_R"
    fi
    [[ $UPDATE_RESHADE == 1 ]] && date +%s > LASTUPDATED
}

function printInstallerBanner() {
    printf '%b%s\n  ReShade installer/updater for Linux games using Wine or Proton.\n  Version %s\n%s%b\n\n' \
        "$_CYN$_B" "$SEPARATOR" "$SCRIPT_VERSION" "$SEPARATOR" "$_R"
}

function printShaderUpdateStatus() {
    if [[ -d "$MAIN_PATH/External_shaders" ]]; then
        printStep "Checking for external shader updates"
        :
    fi
    echo "$SEPARATOR"
}

function ensureRequestedReshadeVersion() {
    local LVERS ALT_URL RHTML VREGEX RLINK RVERS

    cd "$MAIN_PATH" || exit
    LVERS=0
    [[ -f LVERS ]] && LVERS=$(< LVERS)
    if [[ $RESHADE_VERSION == latest ]]; then
        [[ $LVERS =~ Addon && $RESHADE_ADDON_SUPPORT -eq 0 ]] && UPDATE_RESHADE=1
        [[ ! $LVERS =~ Addon && $RESHADE_ADDON_SUPPORT -eq 1 ]] && UPDATE_RESHADE=1
    fi
    if [[ $FORCE_RESHADE_UPDATE_CHECK -eq 1 ]] || [[ $UPDATE_RESHADE -eq 1 ]] || [[ ! -e reshade/latest/ReShade64.dll ]] || [[ ! -e reshade/latest/ReShade32.dll ]]; then
        printStep "Checking for ReShade updates"
        ALT_URL=0
        if ! RHTML=$(curl --fail --max-time 10 -sL "$RESHADE_URL") || [[ $RHTML == *'<h2>Something went wrong.</h2>'* ]]; then
            ALT_URL=1
            echo "Error: Failed to connect to '$RESHADE_URL' after 10 seconds. Trying to connect to '$RESHADE_URL_ALT'."
            RHTML=$(curl --fail --max-time 15 -sL "$RESHADE_URL_ALT") || echo "Error: Failed to connect to '$RESHADE_URL_ALT'."
        fi
        [[ $RESHADE_ADDON_SUPPORT -eq 1 ]] && VREGEX="[0-9][0-9.]*[0-9]_Addon" || VREGEX="[0-9][0-9.]*[0-9]"
        RLINK="$(grep -o "/downloads/ReShade_Setup_${VREGEX}\.exe" <<< "$RHTML" | head -n1)"
        [[ -z $RLINK ]] && printErr "Could not fetch ReShade version."
        [[ $ALT_URL -eq 1 ]] && RLINK="${RESHADE_URL_ALT}${RLINK}" || RLINK="${RESHADE_URL}${RLINK}"
        RVERS=$(grep -o "$VREGEX" <<< "$RLINK")
        if [[ $RVERS != "$LVERS" ]]; then
            [[ -L $RESHADE_PATH/latest ]] && unlink "$RESHADE_PATH/latest"
            printf '%bUpdating ReShade to version %s...%b\n' "$_GRN" "$RVERS" "$_R"
            withProgress "Downloading ReShade $RVERS..." downloadReshade "$RVERS" "$RLINK"
            ln -sf "$(realpath "$RESHADE_PATH/$RVERS")" "$(realpath "$RESHADE_PATH/latest")"
            echo "$RVERS" > LVERS
            LVERS="$RVERS"
            printf '%bReShade updated to %b%s%b.%b\n' "$_GRN" "$_CYN$_B" "$RVERS" "$_R$_GRN" "$_R"
        fi
    fi

    cd "$MAIN_PATH" || exit
    if [[ $RESHADE_VERSION != latest ]]; then
        [[ $RESHADE_ADDON_SUPPORT -eq 1 ]] && RESHADE_VERSION="${RESHADE_VERSION}_Addon"
        if [[ ! -f reshade/$RESHADE_VERSION/ReShade64.dll ]] || [[ ! -f reshade/$RESHADE_VERSION/ReShade32.dll ]]; then
            printf 'Downloading version %s of ReShade.\n%s\n\n' "$RESHADE_VERSION" "$SEPARATOR"
            [[ -e reshade/$RESHADE_VERSION ]] && rm -rf "reshade/$RESHADE_VERSION"
            withProgress "Downloading ReShade $RESHADE_VERSION..." \
                downloadReshade "$RESHADE_VERSION" "$RESHADE_URL/downloads/ReShade_Setup_$RESHADE_VERSION.exe"
        fi
        printf '%bUsing ReShade version %b%s%b.%b\n\n' "$_GRN" "$_CYN$_B" "$RESHADE_VERSION" "$_R$_GRN" "$_R"
    else
        printf '%bUsing the latest version of ReShade (%b%s%b).%b\n\n' "$_GRN" "$_CYN$_B" "$LVERS" "$_R$_GRN" "$_R"
    fi
}

function maybeHandleVulkanFlow() {
    local _useVulkan _startDir _prefixConfirmed _archPick _archChoice _vulkanAction _vPick

    [[ $VULKAN_SUPPORT == 1 ]] || return

    _useVulkan="n"
    if [[ $_UI_BACKEND != cli ]]; then
        ui_yesno "ReShade" "Does this game use the Vulkan API?" 10 60 && _useVulkan="y"
    else
        echo "Does the game use the Vulkan API?"
        _useVulkan=$(checkStdin "(y/n): " "^(y|n)$") || exit 1
    fi
    [[ $_useVulkan == "y" ]] || return

    if [[ $_UI_BACKEND != cli ]]; then
        _startDir="$HOME/.local/share/Steam/steamapps/compatdata"
        [[ ! -d $_startDir ]] && _startDir="$HOME"
        while true; do
            WINEPREFIX=$(ui_directorybox "ReShade - Select WINEPREFIX folder" "$_startDir") || exit 0
            [[ -z $WINEPREFIX ]] && exit 0
            WINEPREFIX="${WINEPREFIX/#\~/$HOME}"
            WINEPREFIX=$(realpath "$WINEPREFIX" 2>/dev/null)
            [[ -d $WINEPREFIX ]] && break
            ui_msgbox "ReShade" "Path does not exist:\n$WINEPREFIX" 12 70
        done
    else
        printf '%bSupply the WINEPREFIX path for the game.%b\n' "$_CYN" "$_R"
        printf '%b(Control+C to exit)%b\n' "$_YLW" "$_R"
        while true; do
            read -rp "$(printf '%bWINEPREFIX path: %b' "$_YLW" "$_R")" WINEPREFIX
            WINEPREFIX="${WINEPREFIX/#\~/$HOME}"
            WINEPREFIX=$(realpath "$WINEPREFIX" 2>/dev/null)
            if [[ -z $WINEPREFIX || ! -d $WINEPREFIX ]]; then
                printf '%bIncorrect or empty path supplied. You supplied "%s".%b\n' "$_YLW" "$WINEPREFIX" "$_R"
                continue
            fi
            printf '%bIs this path correct? "%s"%b\n' "$_YLW" "$WINEPREFIX" "$_R"
            _prefixConfirmed=$(checkStdin "(y/n) " "^(y|n)$") || exit 1
            [[ $_prefixConfirmed == "y" ]] && break
        done
    fi

    if [[ $_UI_BACKEND != cli ]]; then
        _archPick=$(ui_radiolist "ReShade" "Select the game's EXE architecture:" \
            12 60 2 64 "64-bit" ON 32 "32-bit" OFF) || exit 0
        [[ $_archPick == 32 ]] && exeArch=32 || exeArch=64
    else
        echo "Specify if the game's EXE file architecture is 32 or 64 bits:"
        _archChoice=$(checkStdin "(32/64) " "^(32|64)$") || exit 1
        [[ $_archChoice == 64 ]] && exeArch=64 || exeArch=32
    fi
    export WINEPREFIX="$WINEPREFIX"

    _vulkanAction="i"
    if [[ $_UI_BACKEND != cli ]]; then
        _vPick=$(ui_radiolist "ReShade" "Install or uninstall Vulkan ReShade?" \
            12 60 2 install "Install" ON uninstall "Uninstall" OFF) || exit 0
        [[ $_vPick == uninstall ]] && _vulkanAction="u"
    else
        echo "Do you want to (i)nstall or (u)ninstall ReShade?"
        _vulkanAction=$(checkStdin "(i/u): " "^(i|u)$") || exit 1
    fi

    if [[ $_vulkanAction == "i" ]]; then
        wine reg ADD HKLM\\SOFTWARE\\Khronos\\Vulkan\\ImplicitLayers /d 0 /t REG_DWORD /v "Z:\\home\\$USER\\$WINE_MAIN_PATH\\reshade\\$RESHADE_VERSION\\ReShade$exeArch.json" -f /reg:"$exeArch" \
            && echo "Done." || echo "An error has occurred."
    else
        wine reg DELETE HKLM\\SOFTWARE\\Khronos\\Vulkan\\ImplicitLayers -f /reg:"$exeArch" \
            && echo "Done." || echo "An error has occurred."
    fi
    exit 0
}

function maybeHandleDirectXUninstall() {
    local _action _pick LINKS link sysDir

    _action="i"
    if [[ $_UI_BACKEND != cli ]]; then
        _pick=$(ui_radiolist "ReShade" "What would you like to do?" \
            12 70 2 install "Install ReShade for a game" ON uninstall "Uninstall ReShade for a game" OFF) || exit 0
        [[ $_pick == uninstall ]] && _action="u"
    else
        echo "Do you want to (i)nstall or (u)ninstall ReShade for a DirectX or OpenGL game?"
        _action=$(checkStdin "(i/u): " "^(i|u)$") || exit 1
    fi
    [[ $_action == "u" ]] || return

    getGamePath
    printf '%bUnlinking ReShade files from:%b %s\n' "$_GRN" "$_R" "$gamePath"
    LINKS="${COMMON_OVERRIDES// /.dll }.dll ReShade.ini ReShade32.json ReShade64.json d3dcompiler_47.dll Shaders Textures ReShade_shaders"
    [[ -n $LINK_PRESET ]] && LINKS="$LINKS $LINK_PRESET"
    for link in $LINKS; do
        if [[ -L $gamePath/$link ]]; then
            echo "Unlinking \"$gamePath/$link\"."
            unlink "$gamePath/$link"
        fi
    done
    if [[ $DELETE_RESHADE_FILES == 1 ]]; then
        echo "Deleting ReShade.log and ReShadePreset.ini"
        rm -f "$gamePath/ReShade.log" "$gamePath/ReShadePreset.ini"
    fi
    if [[ -n $WINEPREFIX ]]; then
        for sysDir in "$WINEPREFIX/drive_c/windows/system32" "$WINEPREFIX/drive_c/windows/syswow64"; do
            if [[ -L "$sysDir/d3dcompiler_47.dll" ]]; then
                echo "Unlinking d3dcompiler_47.dll from '$sysDir'."
                unlink "$sysDir/d3dcompiler_47.dll"
            fi
        done
    fi
    _selectedGameKey="$(buildGameInstallKey "$_selectedAppId" "$gamePath")"
    if [[ -n $_selectedGameKey ]]; then
        [[ -f "$MAIN_PATH/game-state/$_selectedGameKey.state" ]] && rm -f "$MAIN_PATH/game-state/$_selectedGameKey.state"
        [[ -d "$MAIN_PATH/game-shaders/$_selectedGameKey" ]] && rm -rf "$MAIN_PATH/game-shaders/$_selectedGameKey"
    fi
    printf '%bFinished uninstalling ReShade for:%b %s\n' "$_GRN$_B" "$_R" "$gamePath"
    printf '%bMake sure to remove or unset the %bWINEDLLOVERRIDES%b environment variable.%b\n' "$_GRN" "$_CYN$_B" "$_R$_GRN" "$_R"
    exit 0
}

function maybeHandleBatchUpdate() {
    local _stateDir _ok _fail _sf _gameKey _dll _arch _gp _repos _appId

    [[ $_BATCH_UPDATE -eq 1 ]] || return

    _stateDir="$MAIN_PATH/game-state"
    if [[ ! -d $_stateDir ]] || ! compgen -G "$_stateDir/*.state" &>/dev/null; then
        printf '%bNo installed games found in state store. Run without --update-all first.%b\n' "$_YLW" "$_R"
        exit 0
    fi
    _ok=0
    _fail=0
    for _sf in "$_stateDir"/*.state; do
        _gameKey="${_sf##*/}"
        _gameKey="${_gameKey%.state}"
        _dll=$(grep '^dll=' "$_sf" | cut -d= -f2 | head -1)
        _arch=$(grep '^arch=' "$_sf" | cut -d= -f2 | head -1)
        _gp=$(grep '^gamePath=' "$_sf" | cut -d= -f2- | head -1)
        _repos=$(readSelectedReposFromState "$_sf")
        _appId=$(grep '^app_id=' "$_sf" | cut -d= -f2- | head -1)
        if [[ ! -d $_gp ]]; then
            printf '%bSkipping game %s — directory not found: %s%b\n' \
                "$_YLW" "$_gameKey" "$_gp" "$_R"
            (( _fail++ ))
            continue
        fi
        printf '%bUpdating %s — %s (%s-bit, %s.dll)%b\n' \
            "$_GRN" "${_appId:-$_gameKey}" "$_gp" "$_arch" "$_dll" "$_R"
        [[ -L "$_gp/$_dll.dll" ]] && unlink "$_gp/$_dll.dll"
        if [[ $_arch == 64 ]]; then
            ln -sf "$(realpath "$RESHADE_PATH/$RESHADE_VERSION/ReShade64.dll")" "$_gp/$_dll.dll"
        else
            ln -sf "$(realpath "$RESHADE_PATH/$RESHADE_VERSION/ReShade32.dll")" "$_gp/$_dll.dll"
        fi
        [[ -L "$_gp/d3dcompiler_47.dll" ]] && unlink "$_gp/d3dcompiler_47.dll"
        ln -sf "$(realpath "$MAIN_PATH/d3dcompiler_47.dll.$_arch")" "$_gp/d3dcompiler_47.dll" 2>/dev/null
        [[ -n $_repos ]] && ensureSelectedShaderRepos "$_repos"
        [[ -L "$_gp/ReShade_shaders" ]] && unlink "$_gp/ReShade_shaders"
        buildGameShaderDir "$_gameKey" "$_repos"
        ln -sf "$(realpath "$MAIN_PATH/game-shaders/$_gameKey")" "$_gp/ReShade_shaders"
        ensureGameIni "$_gp"
        ensureGamePreset "$_gp"
        (( _ok++ ))
    done
    printf '%bBatch update complete: %d game(s) updated, %d skipped.%b\n' \
        "$_GRN$_B" "$_ok" "$_fail" "$_R"
    exit 0
}

function autoDetectWineprefixFromGamePath() {
    local _steamRoot _pfx _gameName _acf _appid

    if [[ -z $WINEPREFIX && $gamePath == */steamapps/common/* ]]; then
        _steamRoot="${gamePath%/steamapps/common/*}"
        _pfx=""
        if [[ -n $_selectedAppId ]]; then
            _pfx="$_steamRoot/steamapps/compatdata/$_selectedAppId/pfx"
        else
            _gameName="${gamePath##*/steamapps/common/}"
            _gameName="${_gameName%%/*}"
            for _acf in "$_steamRoot/steamapps"/appmanifest_*.acf; do
                [[ -f $_acf ]] || continue
                if grep -qF "\"$_gameName\"" "$_acf" 2>/dev/null; then
                    _appid=$(grep -o '"appid"[[:space:]]*"[0-9]*"' "$_acf" | grep -o '[0-9]*' | head -1)
                    [[ -n $_appid ]] && _pfx="$_steamRoot/steamapps/compatdata/$_appid/pfx"
                    break
                fi
            done
        fi
        if [[ -n $_pfx && -d $_pfx ]]; then
            export WINEPREFIX="$_pfx"
            printf '%bAuto-detected WINEPREFIX:%b %s\n' "$_GRN" "$_R" "$WINEPREFIX"
        fi
    fi
}

function linkGameFilesForInstall() {
    printStep "Linking ReShade files to game directory"
    [[ -L $gamePath/$wantedDll.dll ]] && unlink "$gamePath/$wantedDll.dll"
    if [[ $exeArch == 32 ]]; then
        printf '%bLinking ReShade32.dll → %s.dll%b\n' "$_GRN" "$wantedDll" "$_R"
        ln -sf "$(realpath "$RESHADE_PATH/$RESHADE_VERSION/ReShade32.dll")" "$gamePath/$wantedDll.dll"
    else
        printf '%bLinking ReShade64.dll → %s.dll%b\n' "$_GRN" "$wantedDll" "$_R"
        ln -sf "$(realpath "$RESHADE_PATH/$RESHADE_VERSION/ReShade64.dll")" "$gamePath/$wantedDll.dll"
    fi
    [[ -L $gamePath/d3dcompiler_47.dll ]] && unlink "$gamePath/d3dcompiler_47.dll"
    ln -sf "$(realpath "$MAIN_PATH/d3dcompiler_47.dll.$exeArch")" "$gamePath/d3dcompiler_47.dll"
    [[ -L $gamePath/ReShade_shaders ]] && unlink "$gamePath/ReShade_shaders"
    printf '%bBuilding per-game shader directory...%b\n' "$_GRN" "$_R"
    buildGameShaderDir "$_selectedGameKey" "$_selectedRepos"
    ln -sf "$(realpath "$MAIN_PATH/game-shaders/$_selectedGameKey")" "$gamePath/ReShade_shaders"
    ensureGameIni "$gamePath"
    ensureGamePreset "$gamePath"
}