# shellcheck shell=bash

# Shader repository registry: entry parsing, labels, default and requested selections.

# Parse a SHADER_REPOS entry into shared variables.
# Format: URL|localname[|branch[|title[|description]]]
function parseShaderRepoEntry() {
    local _entry="$1"
    local _savedIFS="$IFS"
    local -a _parts=()

    IFS='|' read -r -a _parts <<< "$_entry"
    IFS="$_savedIFS"

    _shaderRepoUri="${_parts[0]:-}"
    _shaderRepoName="${_parts[1]:-}"
    _shaderRepoBranch="${_parts[2]:-}"
    _shaderRepoTitle="${_parts[1]:-}"
    _shaderRepoDesc=""

    if (( ${#_parts[@]} == 4 )); then
        _shaderRepoDesc="${_parts[3]:-}"
    elif (( ${#_parts[@]} >= 5 )); then
        _shaderRepoTitle="${_parts[3]:-}"
        _shaderRepoDesc="${_parts[4]:-}"
    fi

    [[ -n $_shaderRepoTitle ]] || _shaderRepoTitle="$_shaderRepoName"

    if [[ -z $_shaderRepoDesc ]]; then
        _shaderRepoDesc="$_shaderRepoUri"
    fi
    return 0
}

function getShaderRepoCreator() {
    local _repoUri="$1"
    if [[ $_repoUri =~ github\.com/([^/]+)/[^/]+/?$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return
    fi
    printf '\n'
}

function formatShaderRepoDisplayLabel() {
    local _repoUri="$1" _repoTitle="$2" _repoDesc="$3"
    local _creator

    _creator=$(getShaderRepoCreator "$_repoUri")
    if [[ -n $_creator ]]; then
        printf '%s by %s | %s\n' "$_repoTitle" "$_creator" "$_repoDesc"
        return
    fi
    printf '%s | %s\n' "$_repoTitle" "$_repoDesc"
}

function listConfiguredShaderRepoEntries() {
    local _savedIFS="$IFS" _entry
    local -A _seen=()

    IFS=';' read -ra _allRepos <<< "$SHADER_REPOS"
    IFS="$_savedIFS"
    for _entry in "${_allRepos[@]}"; do
        parseShaderRepoEntry "$_entry"
        [[ -z $_shaderRepoName ]] && continue
        [[ -n ${_seen["$_shaderRepoName"]+x} ]] && continue
        _seen["$_shaderRepoName"]=1
        printf '%s\n' "$_entry"
    done
}

function collectSelectedInstalledShaderRepos() {
    local _selectedRepos="$1"
    local -n _reposRef="$2"
    local _entry

    _reposRef=()
    [[ -z $_selectedRepos ]] && return 0

    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        repoIsSelected "$_selectedRepos" "$_shaderRepoName" || continue
        [[ -d "$MAIN_PATH/ReShade_shaders/$_shaderRepoName" ]] || continue
        _reposRef+=("$_shaderRepoName")
    done < <(listConfiguredShaderRepoEntries)
}

function listExcludedShaderEffectsForApp() {
    local _appId="$1"
    local _entry _ruleAppId _effects _effect

    [[ -n $_appId ]] || return 0
    [[ -n ${SHADER_EFFECT_EXCLUDES:-} ]] || return 0

    while IFS= read -r _entry || [[ -n $_entry ]]; do
        _ruleAppId=${_entry%%|*}
        _effects=${_entry#*|}
        [[ $_ruleAppId == "$_appId" ]] || continue
        IFS=',' read -ra _effectList <<< "$_effects"
        for _effect in "${_effectList[@]}"; do
            _effect="${_effect#"${_effect%%[![:space:]]*}"}"
            _effect="${_effect%"${_effect##*[![:space:]]}"}"
            [[ -n $_effect ]] && printf '%s\n' "$_effect"
        done
    done < <(printf '%s' "$SHADER_EFFECT_EXCLUDES" | tr ';' '\n')
}

# Return a comma-separated list of all configured shader repo names.
function getDefaultSelectedRepos() {
    local -a _names=()
    local _entry

    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        _names+=("$_shaderRepoName")
    done < <(listConfiguredShaderRepoEntries)

    local IFS=','
    printf '%s\n' "${_names[*]}"
}

# Return the curated first-run subset, preserving configured repo order.
# Falls back to all configured repos if none of the preferred names exist.
function getFirstRunSelectedRepos() {
    local _preferred="${FIRST_RUN_SHADER_REPOS:-}"
    local _entry
    local -a _preferredNames=() _selectedNames=()
    local -A _preferredMap=()

    [[ -n $_preferred ]] || {
        getDefaultSelectedRepos
        return
    }

    IFS=',' read -ra _preferredNames <<< "$_preferred"
    for _entry in "${_preferredNames[@]}"; do
        _entry="${_entry#"${_entry%%[![:space:]]*}"}"
        _entry="${_entry%"${_entry##*[![:space:]]}"}"
        [[ -n $_entry ]] && _preferredMap["$_entry"]=1
    done

    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        [[ -n ${_preferredMap["$_shaderRepoName"]+x} ]] || continue
        _selectedNames+=("$_shaderRepoName")
    done < <(listConfiguredShaderRepoEntries)

    if [[ ${#_selectedNames[@]} -eq 0 ]]; then
        getDefaultSelectedRepos
        return
    fi

    local IFS=','
    printf '%s\n' "${_selectedNames[*]}"
}

function normalizeRequestedShaderRepos() {
    local _requested="$1"
    local _entry _requestedName _normalized
    local -a _requestedNames=() _selectedNames=()
    local -A _known=() _selected=()

    _requested="${_requested#"${_requested%%[![:space:]]*}"}"
    _requested="${_requested%"${_requested##*[![:space:]]}"}"
    case "$_requested" in
        ""|none|NONE)
            printf '\n'
            return 0
            ;;
        all|ALL)
            getDefaultSelectedRepos
            return 0
            ;;
    esac

    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        _known["$_shaderRepoName"]=1
    done < <(listConfiguredShaderRepoEntries)

    IFS=',' read -ra _requestedNames <<< "$_requested"
    for _requestedName in "${_requestedNames[@]}"; do
        _normalized="${_requestedName#"${_requestedName%%[![:space:]]*}"}"
        _normalized="${_normalized%"${_normalized##*[![:space:]]}"}"
        [[ -z $_normalized ]] && continue
        [[ -n ${_known["$_normalized"]+x} ]] || {
            printf 'Unknown shader repository: %s\n' "$_normalized" >&2
            return 1
        }
        _selected["$_normalized"]=1
    done

    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        [[ -n ${_selected["$_shaderRepoName"]+x} ]] || continue
        _selectedNames+=("$_shaderRepoName")
    done < <(listConfiguredShaderRepoEntries)

    local IFS=','
    printf '%s\n' "${_selectedNames[*]}"
}

function getAvailableSelectedRepos() {
    local _selectedRepos="$1"
    local -a _available=()

    collectSelectedInstalledShaderRepos "$_selectedRepos" _available

    local IFS=','
    printf '%s\n' "${_available[*]}"
}
