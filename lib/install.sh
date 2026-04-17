# shellcheck shell=bash

# Downloads d3dcompiler_47.dll files.
# Sources from mozilla/fxc2 GitHub, same source used by Winetricks.
function downloadD3dcompiler_47() {
    ! [[ $1 =~ ^(32|64)$ ]] && printErr "(downloadD3dcompiler_47): Wrong system architecture."
    [[ -f $MAIN_PATH/d3dcompiler_47.dll.$1 ]] && return
    printf '%bDownloading d3dcompiler_47.dll (%s-bit)...%b\n' "$_GRN" "$1" "$_R"
    createTempDir
    if [[ $1 -eq 32 ]]; then
        local url="https://raw.githubusercontent.com/mozilla/fxc2/master/dll/d3dcompiler_47_32.dll"
        local hash="2ad0d4987fc4624566b190e747c9d95038443956ed816abfd1e2d389b5ec0851"
    else
        local url="https://raw.githubusercontent.com/mozilla/fxc2/master/dll/d3dcompiler_47.dll"
        local hash="4432bbd1a390874f3f0a503d45cc48d346abc3a8c0213c289f4b615bf0ee84f3"
    fi
    curl --fail "${_CURL_PROG[@]}" -Lo d3dcompiler_47.dll "$url" \
        || printErr "(downloadD3dcompiler_47) Could not download d3dcompiler_47.dll."
    local dlhash _
    read -r dlhash _ < <(sha256sum d3dcompiler_47.dll)
    [[ "$dlhash" != "$hash" ]] && printErr "(downloadD3dcompiler_47) Integrity check failed. (Expected: $hash ; Calculated: $dlhash)"
    cp d3dcompiler_47.dll "$MAIN_PATH/d3dcompiler_47.dll.$1" || printErr "(downloadD3dcompiler_47) Unable to copy d3dcompiler_47.dll to $MAIN_PATH"
    removeTempDir
}

function validateReshadeDownloadUrl() {
    local _url="$1"

    case "$_url" in
        https://reshade.me/downloads/ReShade_Setup_*.exe|https://static.reshade.me/downloads/ReShade_Setup_*.exe)
            return 0
            ;;
        *)
            printErr "Refusing to download ReShade from an unexpected URL: $_url"
            return 1
            ;;
    esac
}

function verifyReshadeDownloadHash() {
    local _file="$1"
    local _expectedHash="${RESHADE_SETUP_SHA256:-}"
    local _actualHash _rest

    [[ -n $_expectedHash ]] || return 0

    read -r _actualHash _rest < <(sha256sum "$_file")
    [[ ${_actualHash,,} == ${_expectedHash,,} ]] || {
        printErr "ReShade download integrity check failed. Expected $_expectedHash but calculated $_actualHash."
        return 1
    }
}

function verifyExtractedReshadePayload() {
    local _payloadDir="${1:-.}"

    [[ -f "$_payloadDir/ReShade32.dll" ]] || {
        printErr "Extracted ReShade payload is missing ReShade32.dll."
        return 1
    }
    [[ -f "$_payloadDir/ReShade64.dll" ]] || {
        printErr "Extracted ReShade payload is missing ReShade64.dll."
        return 1
    }
}

# Download / extract ReShade from specified link.
# $1 => Version of ReShade
# $2 -> Full URL of ReShade exe, ex.: https://reshade.me/downloads/ReShade_Setup_5.0.2.exe
function downloadReshade() {
    local exeFile resCurPath
    validateReshadeDownloadUrl "$2" || return 1
    createTempDir
    if ! curl --fail "${_CURL_PROG[@]}" -LO "$2"; then
        removeTempDir
        printErr "Could not download version $1 of ReShade."
        return 1
    fi
    exeFile="${2##*/}"
    if ! [[ -f "$exeFile" ]]; then
        removeTempDir
        printErr "Download of ReShade exe file failed."
        return 1
    fi
    if ! file "$exeFile" | grep -q executable; then
        removeTempDir
        printErr "The ReShade exe file is not an executable file, does the ReShade version exist?"
        return 1
    fi
    verifyReshadeDownloadHash "$exeFile" || {
        removeTempDir
        return 1
    }
    if ! 7z -y e "$exeFile" 1> /dev/null; then
        removeTempDir
        printErr "Failed to extract ReShade using 7z."
        return 1
    fi
    rm -f "$exeFile"
    if ! compgen -G './*' > /dev/null; then
        removeTempDir
        printErr "ReShade archive extraction produced no files."
        return 1
    fi
    verifyExtractedReshadePayload "." || {
        removeTempDir
        return 1
    }
    resCurPath="$RESHADE_PATH/$1"
    [[ -e $resCurPath ]] && rm -rf "$resCurPath"
    mkdir -p "$resCurPath"
    if ! mv ./* "$resCurPath"; then
        removeTempDir
        printErr "Failed to move extracted ReShade files into $resCurPath."
        return 1
    fi
    removeTempDir
}

# Link d3dcompiler_47.dll into the Wine/Proton prefix system32 or syswow64 directory.
# Since ReShade 6.5+, the DLL must exist there for shaders to compile correctly.
# $1 is the exe architecture (32 or 64).
function linkD3dcompilerToWineprefix() {
    [[ -z $WINEPREFIX ]] && return
    local arch="$1"
    local sysDir
    # 32-bit libraries go into syswow64 in a 64-bit prefix; 64-bit go into system32.
    if [[ $arch -eq 32 ]] && [[ -d "$WINEPREFIX/drive_c/windows/syswow64" ]]; then
        sysDir="$WINEPREFIX/drive_c/windows/syswow64"
    else
        sysDir="$WINEPREFIX/drive_c/windows/system32"
    fi
    if [[ ! -d $sysDir ]]; then
        printf '%bWarning: Wine prefix directory '\''%s'\'' not found -- skipping system32 d3dcompiler_47.dll install.%b\n' "$_YLW" "$sysDir" "$_R"
        return
    fi
    printf '%bLinking d3dcompiler_47.dll into %b%s%b (required for ReShade 6.5+).%b\n' "$_GRN" "$_CYN" "$sysDir" "$_GRN" "$_R"
    [[ -L "$sysDir/d3dcompiler_47.dll" ]] && unlink "$sysDir/d3dcompiler_47.dll"
    ln -sf "$(realpath "$MAIN_PATH/d3dcompiler_47.dll.$arch")" "$sysDir/d3dcompiler_47.dll"
}

function selectInstallGameTarget() {
    _selectedAppId=""
    _selectedGameKey=""
    _stateFile=""

    getGamePath
    if [[ -z $gamePath || ! -d $gamePath ]]; then
        printf '%bError:%b No valid game path was selected. Aborting before linking.\n' "$_RED$_B" "$_R" >&2
        exit 1
    fi

    _selectedGameKey="$(buildGameInstallKey "$_selectedAppId" "$gamePath")"
    [[ -n $_selectedGameKey ]] && _stateFile="$MAIN_PATH/game-state/$_selectedGameKey.state"
}

function resolveInstallDllSelection() {
    exeArch=32
    wantedDll=""

    if [[ -f "$_stateFile" ]] && loadGameState "$_stateFile" _stored_dll _stored_arch _stored_gamePath _stored_selectedRepos _stored_appId; then
        if [[ -n $_stored_dll && $_stored_arch =~ ^(32|64)$ ]]; then
            wantedDll="$_stored_dll"
            exeArch="$_stored_arch"
            printf '%bReusing stored settings for this game: %s-bit, %s.dll%b\n' \
                "$_GRN" "$exeArch" "$wantedDll" "$_R"
        fi
    fi

    if [[ ${CLI_DLL_OVERRIDE_SET:-0} -eq 1 ]]; then
        wantedDll="$CLI_DLL_OVERRIDE"
        printf '%bUsing CLI DLL override:%b %s.dll\n' "$_GRN" "$_R" "$wantedDll"
    fi

    if [[ -z $wantedDll ]]; then
        _peResult=$(detectExeInfo "$gamePath")
        if [[ -n $_peResult ]]; then
            _pe_arch=$(grep '^arch=' <<< "$_peResult" | cut -d= -f2)
            _pe_dll=$(grep '^dll=' <<< "$_peResult" | cut -d= -f2)
            [[ -n $_pe_arch ]] && exeArch="$_pe_arch"
            [[ -n $_pe_dll ]] && wantedDll="$_pe_dll"
        fi

        if [[ -z $wantedDll ]]; then
            for file in "$gamePath/"*.exe; do
                [[ -f $file ]] || continue
                if [[ $(file "$file" 2>/dev/null) =~ x86-64 ]]; then
                    exeArch=64
                    break
                fi
            done
            [[ $exeArch -eq 32 ]] && wantedDll="d3d9" || wantedDll="dxgi"
        fi

        if [[ $_UI_BACKEND != cli ]]; then
            ui_yesno "ReShade" \
                "Detected a $exeArch-bit game. Use $wantedDll.dll as the DLL override?\n\nCommon overrides: d3d9, dxgi, d3d11, opengl32, ddraw, dinput8." \
                14 78 || wantedDll="manual"
        else
            printf '%bDetected %s-bit game — DLL override: %s.dll. Is this correct?%b\n' \
                "$_CYN" "$exeArch" "$wantedDll" "$_R"
            _dllConfirmed=$(checkStdin "(y/n) " "^(y|n)$") || exit 1
            [[ $_dllConfirmed == "n" ]] && wantedDll="manual"
        fi
    fi

    if [[ $wantedDll == "manual" ]]; then
        if [[ $_UI_BACKEND != cli ]]; then
            while true; do
                wantedDll=$(ui_inputbox "ReShade" \
                    "Enter the DLL override for ReShade. Common values: $COMMON_OVERRIDES" \
                    "dxgi") || exit 0
                wantedDll=${wantedDll//.dll/}
                [[ -n $wantedDll ]] && break
                ui_msgbox "ReShade" "Please enter a DLL name." 10 50
            done
        else
            printf '%bManually enter the dll override for ReShade.%b Common values: %b%s%b\n' "$_CYN" "$_R" "$_B" "$COMMON_OVERRIDES" "$_R"
            while true; do
                read -rp "$(printf '%bOverride: %b' "$_YLW" "$_R")" wantedDll
                wantedDll=${wantedDll//.dll/}
                printf '%bYou entered %b%s%b — is this correct?%b\n' "$_YLW" "$_CYN$_B" "$wantedDll" "$_R$_YLW" "$_R"
                read -rp "$(printf '%b(y/n): %b' "$_YLW" "$_R")" ynCheck
                [[ $ynCheck =~ ^(y|Y|yes|YES)$ ]] && break
            done
        fi
    fi
}

function resolveInstallShaderSelection() {
    _selectedRepos=""
    _requestedSelectedRepos=""
    _shaderDownloadSuccess=0
    _failedRepos=""

    [[ -n $SHADER_REPOS ]] || return 0

    if [[ -f ${_stateFile:-} ]]; then
        _prevRepos=$(readSelectedReposFromState "$_stateFile")
    else
        _prevRepos=$(getFirstRunSelectedRepos)
    fi

    if [[ ${CLI_SHADER_REPOS_SET:-0} -eq 1 ]]; then
        _selectedRepos="$CLI_SHADER_REPOS"
    else
        _selectedRepos=$(selectShaders "$_prevRepos") || exit 0
    fi

    if [[ -n $_selectedRepos ]]; then
        _requestedSelectedRepos="$_selectedRepos"
        printf '%bSelected shader repos:%b %s\n' "$_GRN" "$_R" "$_selectedRepos"
        if ensureSelectedShaderReposWithRetry "$_selectedRepos"; then
            _shaderDownloadSuccess=1
        fi
        _selectedRepos=$(getAvailableSelectedRepos "$_requestedSelectedRepos")
        if [[ $_selectedRepos != "$_requestedSelectedRepos" ]]; then
            printf '%bLinking available shader repos only:%b %s\n' "$_YLW" "$_R" "${_selectedRepos:-<none>}"
        fi
        return 0
    fi

    printf '%bNo shader repos selected — ReShade will have no shaders linked.%b\n' "$_YLW" "$_R"
}

function linkGameFilesForInstall() {
    logDebug "linkGameFilesForInstall start gamePath=$gamePath dll=$wantedDll arch=$exeArch repos=${_selectedRepos:-<none>}"
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
    if [[ -L $gamePath/ReShade_shaders ]]; then
        unlink "$gamePath/ReShade_shaders"
    elif [[ -d $gamePath/ReShade_shaders ]]; then
        rm -rf "$gamePath/ReShade_shaders"
    fi
    printf '%bBuilding per-game shader directory...%b\n' "$_GRN" "$_R"
    buildGameShaderDir "$_selectedGameKey" "$_selectedRepos" "$_selectedAppId"
    ln -sf "$(realpath "$MAIN_PATH/game-shaders/$_selectedGameKey")" "$gamePath/ReShade_shaders"
    ensureGameIni "$gamePath"
    ensureGamePreset "$gamePath"
    logDebug "linkGameFilesForInstall finish gamePath=$gamePath dll=$wantedDll arch=$exeArch"
}