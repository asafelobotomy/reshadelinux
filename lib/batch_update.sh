# shellcheck shell=bash
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck disable=SC2153,SC2154

# --update-all: re-link ReShade and rebuild the shaders of every game with a state file.

function validateBatchUpdateState() {
    local _stateFile="$1"
    local _dll _arch _gp _selectedRepos _appId

    loadGameState "$_stateFile" _dll _arch _gp _selectedRepos _appId || return 1

    [[ $_arch =~ ^(32|64)$ ]] || return 1
    isKnownDllOverride "$_dll" || return 1
    [[ -n $_gp ]] || return 1

    _gp=$(realpath "$_gp" 2>/dev/null || printf '%s' "$_gp")
    [[ -d $_gp ]] || return 1
}

function batchUpdateGameFromState() {
    local _stateFile="$1" _gameKey="$2" _requestedRepos="$3"
    local _dll _arch _gp _savedRepos _appId _effectiveRepos _reshadeDllPath _compilerDllPath

    if ! validateBatchUpdateState "$_stateFile"; then
        printf '%bSkipping game %s — invalid or stale state file: %s%b\n' \
            "$_YLW" "$_gameKey" "$_stateFile" "$_R"
        return 1
    fi

    loadGameState "$_stateFile" _dll _arch _gp _savedRepos _appId || return 1

    if [[ $_arch == 64 ]]; then
        _reshadeDllPath="$RESHADE_PATH/$RESHADE_VERSION/ReShade64.dll"
    else
        _reshadeDllPath="$RESHADE_PATH/$RESHADE_VERSION/ReShade32.dll"
    fi
    _compilerDllPath="$MAIN_PATH/d3dcompiler_47.dll.$_arch"
    if [[ ! -f $_reshadeDllPath || ! -f $_compilerDllPath ]]; then
        printf '%bSkipping game %s — required ReShade files for %s-bit update are missing.%b\n' \
            "$_YLW" "$_gameKey" "$_arch" "$_R"
        return 1
    fi

    printf '%bUpdating %s — %s (%s-bit, %s.dll)%b\n' \
        "$_GRN" "${_appId:-$_gameKey}" "$_gp" "$_arch" "$_dll" "$_R"
    [[ -L "$_gp/$_dll.dll" ]] && unlink "$_gp/$_dll.dll"
    ln -sf "$(realpath "$_reshadeDllPath")" "$_gp/$_dll.dll"
    [[ -L "$_gp/d3dcompiler_47.dll" ]] && unlink "$_gp/d3dcompiler_47.dll"
    ln -sf "$(realpath "$_compilerDllPath")" "$_gp/d3dcompiler_47.dll"
    [[ -n $_requestedRepos ]] && ensureSelectedShaderRepos "$_requestedRepos"
    _effectiveRepos=$(getAvailableSelectedRepos "$_requestedRepos")
    if [[ $_effectiveRepos != "$_requestedRepos" ]]; then
        printf '%bBatch update for %s will link available shader repos only:%b %s\n' \
            "$_YLW" "${_appId:-$_gameKey}" "$_R" "${_effectiveRepos:-<none>}"
    fi
    detachGameShaderDir "$_gp"
    buildGameShaderDir "$_gameKey" "$_effectiveRepos" "$_appId"
    ln -sf "$(realpath "$MAIN_PATH/game-shaders/$_gameKey")" "$_gp/ReShade_shaders"
    ensureGameIni "$_gp"
    ensureGamePreset "$_gp"
    writeGameState "$_gameKey" "$_gp" "$_dll" "$_arch" "$_effectiveRepos" "$_appId"
    return 0
}

# True when at least one game has a tracked install state.
function hasTrackedGames() {
    [[ -d "$MAIN_PATH/game-state" ]] && compgen -G "$MAIN_PATH/game-state/*.state" &>/dev/null
}

# --update-all with nothing tracked has no work to do: leave before ReShade is
# fetched or any download tool is required.
function exitWhenBatchUpdateHasNothingToDo() {
    [[ $_BATCH_UPDATE -eq 1 ]] || return 0
    hasTrackedGames && return 0
    printf '%bNo installed games found in state store. Run without --update-all first.%b\n' "$_YLW" "$_R"
    exit 0
}

function maybeHandleBatchUpdate() {
    local _stateDir _ok _fail _sf _gameKey _requestedRepos _summary

    [[ $_BATCH_UPDATE -eq 1 ]] || return

    exitWhenBatchUpdateHasNothingToDo
    if isDryRun; then
        describeBatchUpdatePlan
        exit 0
    fi
    _stateDir="$MAIN_PATH/game-state"
    _ok=0
    _fail=0
    for _sf in "$_stateDir"/*.state; do
        _gameKey="${_sf##*/}"
        _gameKey="${_gameKey%.state}"
        if [[ ${CLI_SHADER_REPOS_SET:-0} -eq 1 ]]; then
            _requestedRepos="$CLI_SHADER_REPOS"
        else
            _requestedRepos=$(readSelectedReposFromState "$_sf")
        fi
        if batchUpdateGameFromState "$_sf" "$_gameKey" "$_requestedRepos"; then
            _ok=$((_ok + 1))
        else
            _fail=$((_fail + 1))
        fi
    done
    printf '%bBatch update complete: %d game(s) updated, %d skipped.%b\n' \
        "$_GRN$_B" "$_ok" "$_fail" "$_R"
    if [[ $_UI_BACKEND == yad ]]; then
        _summary="Updated $_ok game(s); skipped $_fail."
        [[ $_fail -eq 0 ]] || _summary+="\n\nA skipped game is missing ReShade files or its folder moved. Install it again from the main menu."
        ui_msgbox "ReShade - Update Complete" "$_summary" 12 70
    fi
    exit 0
}
