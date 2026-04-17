# shellcheck shell=bash

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

# Rebuild a per-game shader directory from the selected repos.
function buildGameShaderDir() {
    local _gameKey="$1" _selectedRepos="$2"
    [[ -z $_gameKey ]] && return 1
    logDebug "buildGameShaderDir start gameKey=$_gameKey repos=${_selectedRepos:-<none>}"
    local _gameShaderDir="$MAIN_PATH/game-shaders/$_gameKey"
    rm -rf "$_gameShaderDir"
    mkdir -p "$_gameShaderDir/Merged/Shaders" "$_gameShaderDir/Merged/Textures"
    local _outBase="$_gameShaderDir/Merged" _entry _currentIndex=0
    local -a _reposToMerge=()

    collectSelectedInstalledShaderRepos "$_selectedRepos" _reposToMerge

    for _entry in "${_reposToMerge[@]}"; do
        _currentIndex=$((_currentIndex + 1))
        setProgressText "Building shader directory\n[$_currentIndex/${#_reposToMerge[@]}] Merging $_entry"
        logDebug "buildGameShaderDir repo $_currentIndex/${#_reposToMerge[@]} name=$_entry"
        printf '%b[%d/%d] Merging shader repo:%b %s\n' \
            "$_CYN$_B" "$_currentIndex" "${#_reposToMerge[@]}" "$_R" "$_entry"
        mergeShaderDirsTo "ReShade_shaders" "$_entry" "$_outBase"
    done
    # Always link .fxh include files from all installed repos, even those
    # not selected for this game.  Header files like ReShade.fxh/ReShadeUI.fxh
    # are shared dependencies that most shader effects #include at compile time.
    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        [[ ! -d "$MAIN_PATH/ReShade_shaders/$_shaderRepoName" ]] && continue
        linkRepoIncludesTo "$MAIN_PATH/ReShade_shaders/$_shaderRepoName" "$_outBase"
    done < <(listConfiguredShaderRepoEntries)
    if [[ -d "$MAIN_PATH/External_shaders" ]]; then
        setProgressText "Building shader directory\n[extra] Merging external shaders"
        logDebug "buildGameShaderDir external shaders"
        printf '%b[extra] Merging external shaders%b\n' "$_CYN$_B" "$_R"
        mergeShaderDirsTo "External_shaders" "" "$_outBase"
        local _file _basename
        for _file in "$MAIN_PATH/External_shaders"/*; do
            [[ ! -f $_file ]] && continue
            _basename="${_file##*/}"
            [[ -L "$_outBase/Shaders/$_basename" ]] && continue
            ln -s "$(realpath "$_file")" "$_outBase/Shaders/"
        done
    fi
    logDebug "buildGameShaderDir finish gameKey=$_gameKey"
}

# Clone or update selected shader repositories; records failures in _failedRepos.
function ensureSelectedShaderRepos() {
    local _selectedRepos="$1"
    [[ -z $_selectedRepos ]] && return 0
    local _entry _status
    _failedRepos=""

    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        repoIsSelected "$_selectedRepos" "$_shaderRepoName" || continue
        if [[ -d "$MAIN_PATH/ReShade_shaders/$_shaderRepoName" ]]; then
            if [[ $UPDATE_RESHADE -eq 1 ]]; then
                cd "$MAIN_PATH/ReShade_shaders/$_shaderRepoName" || continue
                printf '%bUpdating shader repo:%b %s\n' "$_GRN" "$_R" "$_shaderRepoUri"
                withProgress "Updating shader repo:\n<tt>$_shaderRepoUri</tt>" \
                    git pull --ff-only
                _status=$?
                if [[ $_status -ne 0 ]]; then
                    printf '%bCould not update shader repo: %s%b\n' "$_YLW" "$_shaderRepoUri" "$_R"
                    _failedRepos="${_failedRepos:+$_failedRepos,}$_shaderRepoName"
                fi
            fi
        else
            mkdir -p "$MAIN_PATH/ReShade_shaders" || exit
            cd "$MAIN_PATH/ReShade_shaders" || exit
            local branchArgs=()
            [[ -n $_shaderRepoBranch ]] && branchArgs=(--branch "$_shaderRepoBranch" --single-branch)
            printf '%bCloning shader repo:%b %s\n' "$_GRN" "$_R" "$_shaderRepoUri"
            withProgress "Cloning shader repo:\n<tt>$_shaderRepoUri</tt>" \
                git clone --depth 1 "${branchArgs[@]}" "$_shaderRepoUri" "$_shaderRepoName"
            _status=$?
            if [[ $_status -ne 0 ]]; then
                printf '%bCould not clone shader repo: %s%b\n' "$_YLW" "$_shaderRepoUri" "$_R"
                _failedRepos="${_failedRepos:+$_failedRepos,}$_shaderRepoName"
            fi
        fi
    done < <(listConfiguredShaderRepoEntries)
    [[ -n $_failedRepos ]] && return 1
    return 0
}

# Create a per-game ReShade.ini when needed.
function ensureGameIni() {
    local _gamePath="$1"
    [[ $GLOBAL_INI == 0 ]] && return 0
    local _target="$_gamePath/ReShade.ini"
    [[ -f $_target ]] && return 0
    if [[ $GLOBAL_INI == ReShade.ini ]]; then
        cat > "$_target" <<'EOF'
[GENERAL]
EffectSearchPaths=.\ReShade_shaders\Merged\Shaders
TextureSearchPaths=.\ReShade_shaders\Merged\Textures
EOF
        return 0
    fi
    [[ -f "$MAIN_PATH/$GLOBAL_INI" ]] || return 1
    cp "$MAIN_PATH/$GLOBAL_INI" "$_target"
}

# Copy the configured preset into the game directory when needed.
function ensureGamePreset() {
    local _gamePath="$1"
    [[ -z $LINK_PRESET ]] && return 0
    [[ -f "$MAIN_PATH/$LINK_PRESET" ]] || return 0
    [[ -f "$_gamePath/$LINK_PRESET" ]] && return 0
    cp "$MAIN_PATH/$LINK_PRESET" "$_gamePath/$LINK_PRESET"
}

# Show the shader repository selection UI and print the chosen repo names.
function selectShaders() {
    local _current="$1"
    local -a _names=() _labels=() _rows=()
    if [[ ${UI_AUTO_CONFIRM:-0} == 1 && $_UI_BACKEND != cli && -z $_current ]]; then
        _current=$(getDefaultSelectedRepos)
    fi
    local _entry _checked _rowKey
    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        _checked="$(repoChecklistState "$_current" "$_shaderRepoName")"
        _names+=("$_shaderRepoName")
        _labels+=("$(formatShaderRepoDisplayLabel "$_shaderRepoUri" "$_shaderRepoTitle" "$_shaderRepoDesc")")
        _rowKey="${#_names[@]}"
        _rows+=("$_rowKey" "${_labels[-1]}" "$_checked")
    done < <(listConfiguredShaderRepoEntries)
    local -a _selected_names=()
    if [[ $_UI_BACKEND != cli ]]; then
        local _term_lines _list_h _box_h
        _term_lines=$(tput lines 2>/dev/null || echo 24)
        _list_h=$(( _term_lines - 10 ))
        (( _list_h < 5 )) && _list_h=5
        (( _list_h > ${#_names[@]} )) && _list_h=${#_names[@]}
        _box_h=$(( _list_h + 8 ))
        local _result
        _result=$(ui_checklist "ReShade - Shader Repositories" \
            "Select which shader repositories to install for this game. Each entry shows the pack title, creator, and a short highlight summary." \
            "$_box_h" 100 "$_list_h" "${_rows[@]}") || return 1
        _result=${_result//\"/}
        if [[ -n $_result ]]; then
            local _selected_index
            while IFS= read -r _selected_index || [[ -n $_selected_index ]]; do
                [[ $_selected_index =~ ^[0-9]+$ ]] || continue
                _selected_names+=("${_names[$((_selected_index - 1))]}")
            done < <(printf '%s' "$_result" | tr '|\n\r\t ' '\n' | sed '/^$/d')
        fi
    else
        printf '%bSelect shader repositories to install for this game:%b\n' "$_CYN" "$_R" >&2
        local _i _ans
        for (( _i=0; _i<${#_names[@]}; _i++ )); do
            local _def="y"
            [[ "${_rows[$(( (_i * 3) + 2 ))]}" == "OFF" ]] && _def="n"
            printf '  [%s] %s\n     Include? [%s]: ' \
                "$(( _i + 1 ))" "${_labels[$_i]}" "$_def" >&2
            read -r _ans
            [[ -z $_ans ]] && _ans="$_def"
            [[ "$_ans" =~ ^(y|Y|yes|YES)$ ]] && _selected_names+=("${_names[$_i]}")
        done
    fi
    local IFS=','
    echo "${_selected_names[*]}"
}

# Link shared .fxh includes from a repo into the merged output.
function linkRepoIncludesTo() {
    local _repoRoot="$1" _outBase="$2" _shadersDir _outDir _file _basename
    if [[ -d "$_repoRoot/Shaders" ]]; then
        _shadersDir="$_repoRoot/Shaders"
    else
        _shadersDir=$(find "$_repoRoot" \
            -maxdepth 4 \
            \( -path '*/.git' -o -path '*/.github' -o -path '*/download' \) -prune -o \
            -type d -name "Shaders" -print -quit)
    fi
    [[ -z $_shadersDir || ! -d $_shadersDir ]] && return
    _outDir="$_outBase/Shaders"
    mkdir -p "$_outDir"
    for _file in "$_shadersDir"/*.fxh; do
        [[ ! -f $_file ]] && continue
        _basename="${_file##*/}"
        [[ -L "$_outDir/$_basename" ]] && continue
        ln -s "$(realpath "$_file")" "$_outDir/"
    done
}

# Link shader files into an arbitrary output base directory.
function linkShaderFilesTo() {
    [[ ! -d $1 ]] && return
    local _inDir="$1" _subDir="$2" _outBase="$3"
    local _outDir="$_outBase/$_subDir"
    mkdir -p "$_outDir"
    local _outDirReal
    _outDirReal="$(realpath "$_outDir")"
    local _file _basename
    for _file in "$_inDir"/*; do
        [[ ! -f $_file ]] && continue
        _basename="${_file##*/}"
        [[ -L "$_outDirReal/$_basename" ]] && continue
        ln -s "$(realpath "$_file")" "$_outDirReal/"
    done
}

# Merge shader directories into an arbitrary output base directory.
function mergeShaderDirsTo() {
    [[ $1 != ReShade_shaders && $1 != External_shaders ]] && return
    local _outBase="$3"
    local _repoRoot="" dirPath

    if [[ $1 == "ReShade_shaders" ]]; then
        _repoRoot="$MAIN_PATH/$1/$2"
    else
        _repoRoot="$MAIN_PATH/$1"
    fi

    for dirName in Shaders Textures; do
        if [[ $1 == "ReShade_shaders" ]]; then
            if [[ -d "$_repoRoot/$dirName" ]]; then
                dirPath="$_repoRoot/$dirName"
            else
                dirPath=$(find "$_repoRoot" \
                    -maxdepth 4 \
                    \( -path '*/.git' -o -path '*/.github' -o -path '*/download' \) -prune -o \
                    -type d -name "$dirName" -print -quit)
            fi
        else
            dirPath="$_repoRoot/$dirName"
        fi
        [[ -z $dirPath || ! -d $dirPath ]] && continue
        linkShaderFilesTo "$dirPath" "$dirName" "$_outBase"
        while IFS= read -rd '' anyDir; do
            linkShaderFilesTo "$dirPath/$anyDir" "$dirName/$anyDir" "$_outBase"
        done < <(cd "$dirPath" && find . -mindepth 1 -type d -print0)
    done
}
