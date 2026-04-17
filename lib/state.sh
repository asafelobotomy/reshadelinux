# shellcheck shell=bash

# Build a stable per-game install key.
# Steam games use the AppID directly; non-Steam games use a path hash.
# $1=appId  $2=gamePath
function buildGameInstallKey() {
    local _aid="$1" _gp="$2"
    if [[ -n $_aid ]]; then
        printf '%s\n' "$_aid"
        return
    fi
    [[ -z $_gp ]] && return 1
    printf 'path-%s\n' "$(printf '%s' "$_gp" | sha256sum | cut -c1-16)"
}

# Write a per-game state file recording installation details.
# $1=gameKey  $2=gamePath  $3=dll  $4=arch  $5=selected_repos  $6=appId(optional)
# State files live in $MAIN_PATH/game-state/<gameKey>.state
function writeGameState() {
    local _gameKey="$1" _gp="$2" _dll="$3" _arch="$4" _repos="$5" _appId="${6:-}"
    [[ -z $_gameKey ]] && return
    local _dir="$MAIN_PATH/game-state"
    mkdir -p "$_dir" 2>/dev/null || return
    printf 'dll=%s\narch=%s\ngamePath=%s\nselected_repos=%s\napp_id=%s\n' \
        "$_dll" "$_arch" "$_gp" "$_repos" "$_appId" > "$_dir/$_gameKey.state"
}

function readGameStateField() {
    local _stateFile="$1" _field="$2"
    [[ -f $_stateFile ]] || return 1
    grep "^${_field}=" "$_stateFile" | cut -d= -f2- | head -1
}

function loadGameState() {
    local _stateFile="$1"
    local -n _dllRef="$2"
    local -n _archRef="$3"
    local -n _gamePathRef="$4"
    local -n _selectedReposRef="$5"
    local -n _appIdRef="$6"

    [[ -f $_stateFile ]] || return 1
    _dllRef=$(readGameStateField "$_stateFile" dll)
    _archRef=$(readGameStateField "$_stateFile" arch)
    _gamePathRef=$(readGameStateField "$_stateFile" gamePath)
    _selectedReposRef=$(readSelectedReposFromState "$_stateFile")
    _appIdRef=$(readGameStateField "$_stateFile" app_id)
}

# Read selected shader repos from a state file.
# Missing fields default to all repos for backward compatibility.
# An explicit empty field means no repos selected.
function readSelectedReposFromState() {
    local _stateFile="$1"
    [[ -f $_stateFile ]] || { getDefaultSelectedRepos; return; }
    if grep -q '^selected_repos=' "$_stateFile" 2>/dev/null; then
        grep '^selected_repos=' "$_stateFile" | cut -d= -f2- | head -1
        return
    fi
    getDefaultSelectedRepos
}

function repoIsSelected() {
    local _selectedRepos="$1" _repoName="$2" _entry
    local _savedIFS="$IFS"
    IFS=',' read -ra _repoList <<< "$_selectedRepos"
    IFS="$_savedIFS"
    for _entry in "${_repoList[@]}"; do
        [[ $_entry == "$_repoName" ]] && return 0
    done
    return 1
}

function repoChecklistState() {
    local _selectedRepos="$1" _repoName="$2"
    repoIsSelected "$_selectedRepos" "$_repoName" && printf 'ON\n' || printf 'OFF\n'
}

function isKnownDllOverride() {
    local _dll="$1" _candidate
    [[ -n $_dll ]] || return 1
    for _candidate in $COMMON_OVERRIDES; do
        [[ $_candidate == "$_dll" ]] && return 0
    done
    return 1
}

function gameHasTrackedInstall() {
    local _appId="$1" _gamePath="$2"
    local _gameKey _stateFile _dll

    _gameKey=$(buildGameInstallKey "$_appId" "$_gamePath") || return 1
    _stateFile="$MAIN_PATH/game-state/$_gameKey.state"
    [[ -f $_stateFile ]] || return 1

    _dll=$(readGameStateField "$_stateFile" dll) || return 1
    isKnownDllOverride "$_dll" || return 1
    [[ -e "$_gamePath/$_dll.dll" || -L "$_gamePath/$_dll.dll" ]]
}

function formatDetectedGameLabel() {
    local _gameName="$1" _appId="$2" _gamePath="$3"
    if gameHasTrackedInstall "$_appId" "$_gamePath"; then
        printf '✔ %s\n' "$_gameName"
        return
    fi
    printf '%s\n' "$_gameName"
}
