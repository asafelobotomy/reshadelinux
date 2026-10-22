# shellcheck shell=bash
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck disable=SC2153,SC2154

function initializeMainWorkspace() {
    if isDryRun; then
        cd "$MAIN_PATH" 2>/dev/null || cd / || exit
        return 0
    fi
    mkdir -p "$MAIN_PATH" || printErr "Unable to create directory '$MAIN_PATH'."
    cd "$MAIN_PATH" || exit

    mkdir -p "$RESHADE_PATH"
    mkdir -p "$MAIN_PATH/ReShade_shaders"
    mkdir -p "$MAIN_PATH/External_shaders"
}

function printInstallerBanner() {
    printf '%b%s\n  ReShade installer/updater for Linux games using Wine or Proton.\n  Version %s\n%s%b\n\n' \
        "$_CYN$_B" "$SEPARATOR" "$SCRIPT_VERSION" "$SEPARATOR" "$_R"
}

function printShaderUpdateStatus() {
    if compgen -G "$MAIN_PATH/External_shaders/*" &>/dev/null; then
        printStep "Checking for external shader updates"
    fi
    echo "$SEPARATOR"
}

function ensureRequestedReshadeVersion() {
    local LVERS ALT_URL RHTML VREGEX RLINK RVERS LASTUPDATED _ago

    cd "$MAIN_PATH" || exit
    LASTUPDATED=0
    [[ -f LASTUPDATED ]] && LASTUPDATED=$(< LASTUPDATED)
    [[ ! $LASTUPDATED =~ ^[0-9]+$ ]] && LASTUPDATED=0
    if [[ $FORCE_RESHADE_UPDATE_CHECK -eq 0 && $UPDATE_RESHADE -eq 1 && $LASTUPDATED -gt 0 && $(($(date +%s) - LASTUPDATED)) -lt 14400 ]]; then
        UPDATE_RESHADE=0
        _ago=$(( ($(date +%s) - LASTUPDATED) / 60 ))
        printf '%bSkipping update check (last checked %d min ago). Set FORCE_RESHADE_UPDATE_CHECK=1 to override.%b\n\n' \
            "$_YLW" "$_ago" "$_R"
    fi
    [[ $UPDATE_RESHADE == 1 ]] && date +%s > LASTUPDATED

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
        [[ -z $RLINK ]] && failWith "$EXIT_NETWORK" "Could not fetch ReShade version."
        [[ $ALT_URL -eq 1 ]] && RLINK="${RESHADE_URL_ALT}${RLINK}" || RLINK="${RESHADE_URL}${RLINK}"
        RVERS=$(grep -o "$VREGEX" <<< "$RLINK")
        _fallBackToPinnedReshade
        if [[ $RVERS != "$LVERS" || ! -f $RESHADE_PATH/$RVERS/ReShade64.dll || ! -f $RESHADE_PATH/$RVERS/ReShade32.dll ]]; then
            printf '%bUpdating ReShade to version %s...%b\n' "$_GRN" "$RVERS" "$_R"
            withProgress "Downloading ReShade $RVERS..." downloadReshade "$RVERS" "$RLINK"
            # Repoint only after the download succeeded so a failure keeps the working link.
            ln -sfn "$(realpath "$RESHADE_PATH/$RVERS")" "$RESHADE_PATH/latest"
            echo "$RVERS" > LVERS
            LVERS="$RVERS"
            printf '%bReShade updated to %b%s%b.%b\n' "$_GRN" "$_CYN$_B" "$RVERS" "$_R$_GRN" "$_R"
        elif [[ ! -e $RESHADE_PATH/latest/ReShade64.dll ]]; then
            ln -sfn "$(realpath "$RESHADE_PATH/$RVERS")" "$RESHADE_PATH/latest"
        fi
    fi

    cd "$MAIN_PATH" || exit
    if [[ $RESHADE_VERSION != latest ]]; then
        [[ $RESHADE_ADDON_SUPPORT -eq 1 ]] && RESHADE_VERSION="${RESHADE_VERSION}_Addon"
        if [[ ! -f reshade/$RESHADE_VERSION/ReShade64.dll ]] || [[ ! -f reshade/$RESHADE_VERSION/ReShade32.dll ]]; then
            reshadeSetupIsAcceptable "$RESHADE_VERSION" \
                || failWith "$EXIT_INTEGRITY" "ReShade $RESHADE_VERSION has no built-in checksum. Pick a pinned version, set RESHADE_SETUP_SHA256 to the digest you expect, or set RESHADE_ALLOW_UNPINNED=1."
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

# A ReShade release newer than this installer's checksums is not installed unverified: the newest
# pinned build is used instead, until reshadelinux is updated. Adjusts RVERS and RLINK in place.
function _fallBackToPinnedReshade() {
    local _pinned

    reshadeSetupIsAcceptable "$RVERS" && return 0
    _pinned=$(newestPinnedReshadeVersion "$RESHADE_ADDON_SUPPORT") \
        || failWith "$EXIT_INTEGRITY" "ReShade $RVERS has no built-in checksum and no other build is pinned. Set RESHADE_SETUP_SHA256 or RESHADE_ALLOW_UNPINNED=1."
    printWarn "ReShade $RVERS is newer than the builds this installer has checksums for, so $_pinned is used. Update reshadelinux to get $RVERS, or set RESHADE_ALLOW_UNPINNED=1 to install it unverified."
    RLINK="${RLINK%/downloads/*}/downloads/ReShade_Setup_$_pinned.exe"
    RVERS="$_pinned"
}

function _notifyShaderDownloadSuccess() {
    if [[ $_UI_BACKEND != cli ]]; then
        ui_msgbox "ReShade - Shaders" "Shaders have been successfully downloaded and will be linked to your game." 10 60
    else
        printf '%b✓ Shaders downloaded successfully.%b\n' "$_GRN" "$_R"
    fi
}

function ensureSelectedShaderReposWithRetry() {
    local _selectedRepos="$1"
    [[ -z $_selectedRepos ]] && return 0

    if ensureSelectedShaderRepos "$_selectedRepos"; then
        _notifyShaderDownloadSuccess
        return 0
    fi

    printf '%b⚠ Some shader repositories failed to download:%b %s\n' "$_YLW" "$_R" "$_failedRepos"
    if [[ $_UI_BACKEND != cli ]]; then
        if ui_yesno "ReShade - Download Error" "Failed to download: $_failedRepos\n\nRetry downloading these repositories?" 10 70; then
            printf '%bRetrying failed repositories...%b\n' "$_CYN" "$_R"
            if ensureSelectedShaderRepos "$_failedRepos"; then
                _notifyShaderDownloadSuccess
                return 0
            fi
            printf '%b⚠ Still unable to download some repositories. Continuing without those shaders.%b\n' "$_YLW" "$_R"
            ui_warnbox "ReShade - Download Error" "Some shader repositories could not be downloaded. Installation will continue without them." 10 60
            return 1
        fi
    elif ! isNoInput; then
        printf '%bRetry downloading failed repositories? (y/n): %b' "$_YLW" "$_R"
        read -r _retry
        if [[ $_retry =~ ^(y|Y|yes|YES)$ ]]; then
            printf '%bRetrying failed repositories...%b\n' "$_CYN" "$_R"
            if ensureSelectedShaderRepos "$_failedRepos"; then
                _notifyShaderDownloadSuccess
                return 0
            fi
            printf '%b⚠ Still unable to download some repositories. Continuing without those shaders.%b\n' "$_YLW" "$_R"
            return 1
        fi
    fi

    printf '%bSkipping failed repositories. Continuing with successful downloads.%b\n' "$_YLW" "$_R"
    return 1
}

# Every name in a game folder that an install may have linked.
function uninstallLinkNames() {
    local _links="${COMMON_OVERRIDES// /.dll }.dll ReShade.ini d3dcompiler_47.dll Shaders Textures ReShade_shaders"
    [[ -n $LINK_PRESET ]] && _links+=" $LINK_PRESET"
    printf '%s\n' "$_links"
}

function performDirectXUninstall() {
    local link sysDir

    getGamePath
    if isDryRun; then
        describeUninstallPlan
        exit 0
    fi
    printf '%bUnlinking ReShade files from:%b %s\n' "$_GRN" "$_R" "$gamePath"
    for link in $(uninstallLinkNames); do
        if [[ -L $gamePath/$link ]]; then
            echo "Unlinking \"$gamePath/$link\"."
            unlink "$gamePath/$link"
        fi
    done
    # ReShade_shaders may be a real directory (manual install / old format).
    detachGameShaderDir "$gamePath"
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
    # whiptail and dialog run in a terminal, where the lines above are already visible.
    if [[ $_UI_BACKEND == yad ]]; then
        ui_msgbox "ReShade - Uninstall Complete" \
            "ReShade was removed from:\n$(uiQuote "$gamePath")\n\nRemove the WINEDLLOVERRIDES setting from the game's Steam launch options." 12 74
    fi
    exit 0
}

function maybeHandleDirectXUninstall() {
    local _action _pick
    local _hasInstalled=0

    [[ $_BATCH_UPDATE -eq 1 ]] && return
    [[ ${CLI_UNINSTALL:-0} -eq 1 ]] && performDirectXUninstall
    # Without --uninstall or --update-all, a run that may not ask is an install.
    isNoInput && return

    # Check if any games are installed (for the update-all option).
    if [[ -d "$MAIN_PATH/game-state" ]] && compgen -G "$MAIN_PATH/game-state/*.state" &>/dev/null; then
        _hasInstalled=1
    fi

    _action="i"
    if [[ $_UI_BACKEND != cli ]]; then
        local -a _radioRows=(install "Install ReShade for a game" ON
                              uninstall "Uninstall ReShade for a game" OFF)
        local _listH=2 _boxH=12
        if [[ $_hasInstalled -eq 1 ]]; then
            _radioRows+=(update-all "Update all installed games" OFF)
            _listH=3
            _boxH=14
        fi
        _pick=$(ui_radiolist "ReShade" "What would you like to do?" \
            "$_boxH" 70 "$_listH" "${_radioRows[@]}") || exit 0
        case "$_pick" in
            uninstall)  _action="u" ;;
            update-all) _action="a" ;;
        esac
    else
        if [[ $_hasInstalled -eq 1 ]]; then
            echo "Do you want to (i)nstall, (u)ninstall, or update (a)ll installed games?"
            _action=$(checkStdin "(i/u/a): " "^(i|u|a)$") || exit 1
        else
            echo "Do you want to (i)nstall or (u)ninstall ReShade for a DirectX or OpenGL game?"
            _action=$(checkStdin "(i/u): " "^(i|u)$") || exit 1
        fi
    fi
    if [[ $_action == "a" ]]; then
        _BATCH_UPDATE=1
        return
    fi
    [[ $_action == "u" ]] || return
    performDirectXUninstall
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
