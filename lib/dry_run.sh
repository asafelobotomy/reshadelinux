# shellcheck shell=bash
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck disable=SC2153,SC2154  # gamePath, wantedDll ... are set by the install flow

# --dry-run: describe what a run would download, link and write. Nothing here creates, changes or
# removes a file, and nothing contacts the network.

function _planLine() {
    printResult "  $*"
}

function _planHeading() {
    printResult ""
    printResult "$*"
}

# The ReShade build a run would use, and whether it is already on disk.
function describeReshadePlan() {
    local _name="$RESHADE_VERSION" _installed="" _pinned=""

    _planHeading "ReShade:"
    if [[ $_name == latest ]]; then
        [[ -f $MAIN_PATH/LVERS ]] && _installed=$(<"$MAIN_PATH/LVERS")
        _pinned=$(newestPinnedReshadeVersion "$RESHADE_ADDON_SUPPORT") || _pinned="none"
        _planLine "version: latest (installed: ${_installed:-none}; newest pinned build: $_pinned)"
        _planLine "a real run checks reshade.me for a newer release, at most every four hours"
        return 0
    fi
    [[ $RESHADE_ADDON_SUPPORT -eq 1 ]] && _name+="_Addon"
    if [[ -f $RESHADE_PATH/$_name/ReShade64.dll && -f $RESHADE_PATH/$_name/ReShade32.dll ]]; then
        _planLine "version: $_name (already downloaded)"
    elif reshadeSetupIsAcceptable "$_name"; then
        _planLine "would download: $RESHADE_URL/downloads/ReShade_Setup_$_name.exe"
    else
        _planLine "would refuse $_name: it has no built-in checksum (see RESHADE_SETUP_SHA256 and RESHADE_ALLOW_UNPINNED)"
    fi
}

# One line per shader pack the selection needs: cloned, moved to its pin, updated, or kept.
function describeShaderRepoPlan() {
    local _selected="$1" _entry _dir _commit _head _action

    _planHeading "Shader packs:"
    if [[ -z $_selected ]]; then
        _planLine "none selected"
        return 0
    fi
    _selected=$(resolveShaderRepoRequirements "$_selected")
    _selected+="${SHADER_CORE_REPOS:+,$SHADER_CORE_REPOS}"
    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        repoIsSelected "$_selected" "$_shaderRepoName" || continue
        _dir="$MAIN_PATH/ReShade_shaders/$_shaderRepoName"
        _commit=$(shaderRepoWantedCommit "$_shaderRepoUri" "$_shaderRepoBranch") || _commit=""
        _head=""
        [[ -d $_dir ]] && { _head=$(_gitNoPrompt -C "$_dir" rev-parse HEAD 2>/dev/null) || _head=""; }
        if [[ ! -d $_dir ]]; then
            _action="would clone"
        elif [[ -n $_commit && $_head == "$_commit" ]]; then
            _action="up to date"
        elif [[ -n $_commit ]]; then
            _action="would move to its pinned commit"
        elif [[ $UPDATE_RESHADE -eq 1 ]]; then
            _action="would update its branch"
        else
            _action="kept as it is"
        fi
        if [[ -n $_commit ]]; then
            _planLine "$_shaderRepoName: $_action (pinned ${_commit:0:12})"
        else
            _planLine "$_shaderRepoName: $_action (follows its branch, not pinned)"
        fi
    done < <(listConfiguredShaderRepoEntries)
}

function describeInstallPlan() {
    local _dllSource="$RESHADE_PATH/$RESHADE_VERSION/ReShade$exeArch.dll" _ini="$gamePath/ReShade.ini"

    printResult "Dry run: nothing was changed."
    describeReshadePlan
    _planHeading "Game: $gamePath${_selectedAppId:+ (App ID $_selectedAppId)}"
    _planLine "would link $wantedDll.dll -> $_dllSource ($exeArch-bit)"
    if [[ -f $MAIN_PATH/d3dcompiler_47.dll.$exeArch ]]; then
        _planLine "would link d3dcompiler_47.dll -> $MAIN_PATH/d3dcompiler_47.dll.$exeArch"
    else
        _planLine "would download d3dcompiler_47.dll ($exeArch-bit, checked against its built-in SHA-256) and link it"
    fi
    if [[ -n $WINEPREFIX ]]; then
        _planLine "would link d3dcompiler_47.dll into the prefix: $WINEPREFIX"
    else
        _planLine "no Wine prefix found: d3dcompiler_47.dll is not linked into one"
    fi
    if [[ -d $gamePath/ReShade_shaders && ! -L $gamePath/ReShade_shaders ]]; then
        _planLine "would move the existing ReShade_shaders folder aside to ReShade_shaders.bak-<timestamp>"
    fi
    _planLine "would rebuild $MAIN_PATH/game-shaders/$_selectedGameKey and link it as ReShade_shaders"
    if [[ $GLOBAL_INI == 0 ]]; then
        _planLine "ReShade.ini: left for ReShade to create (GLOBAL_INI=0)"
    elif [[ -f $_ini ]]; then
        _planLine "ReShade.ini: kept (search paths corrected if this installer wrote them)"
    else
        _planLine "ReShade.ini: would be created"
    fi
    _planLine "would record the install in $MAIN_PATH/game-state/$_selectedGameKey.state"
    describeShaderRepoPlan "$_selectedRepos"
    _planHeading "Launch option: WINEDLLOVERRIDES=\"d3dcompiler_47=n;$wantedDll=n,b\" %command%"
}

function describeUninstallPlan() {
    local _link _found=0 _sysDir _key

    printResult "Dry run: nothing was changed."
    _planHeading "Would remove ReShade from: $gamePath"
    for _link in $(uninstallLinkNames); do
        [[ -L $gamePath/$_link ]] || continue
        _planLine "would unlink $_link"
        _found=1
    done
    if [[ -d $gamePath/ReShade_shaders && ! -L $gamePath/ReShade_shaders ]]; then
        _planLine "would move the ReShade_shaders folder aside to ReShade_shaders.bak-<timestamp>"
        _found=1
    fi
    [[ $_found -eq 1 ]] || _planLine "no ReShade links found in the game folder"
    if [[ $DELETE_RESHADE_FILES == 1 ]]; then
        _planLine "would delete ReShade.log and ReShadePreset.ini"
    fi
    if [[ -n $WINEPREFIX ]]; then
        for _sysDir in "$WINEPREFIX/drive_c/windows/system32" "$WINEPREFIX/drive_c/windows/syswow64"; do
            [[ -L $_sysDir/d3dcompiler_47.dll ]] && _planLine "would unlink $_sysDir/d3dcompiler_47.dll"
        done
    fi
    _key="$(buildGameInstallKey "$_selectedAppId" "$gamePath")"
    [[ -n $_key && -f $MAIN_PATH/game-state/$_key.state ]] && _planLine "would delete its state file and per-game shader folder"
    return 0
}

function describeBatchUpdatePlan() {
    local _sf _gameKey _dll _arch _gp _repos _appId _requested

    printResult "Dry run: nothing was changed."
    describeReshadePlan
    for _sf in "$MAIN_PATH/game-state"/*.state; do
        _gameKey="${_sf##*/}"
        _gameKey="${_gameKey%.state}"
        if ! validateBatchUpdateState "$_sf"; then
            _planHeading "Would skip $_gameKey: invalid or stale state file"
            continue
        fi
        loadGameState "$_sf" _dll _arch _gp _repos _appId || continue
        _requested="$_repos"
        [[ ${CLI_SHADER_REPOS_SET:-0} -eq 1 ]] && _requested="$CLI_SHADER_REPOS"
        _planHeading "Would update ${_appId:-$_gameKey}: $_gp"
        _planLine "would re-link $_dll.dll ($_arch-bit) and d3dcompiler_47.dll"
        _planLine "shader packs: ${_requested:-none}"
    done
}
