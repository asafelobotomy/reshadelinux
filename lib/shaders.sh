# shellcheck shell=bash

# Parse a SHADER_REPOS entry into shared variables.
# Format: URL|localname[|branch[|description]]
function parseShaderRepoEntry() {
    local _entry="$1"
    local _savedIFS="$IFS"
    IFS='|' read -r _shaderRepoUri _shaderRepoName _shaderRepoBranch _shaderRepoDesc <<< "$_entry"
    IFS="$_savedIFS"
    [[ -z $_shaderRepoDesc ]] && _shaderRepoDesc="$_shaderRepoUri"
}

# Return a comma-separated list of all configured shader repo names.
function getDefaultSelectedRepos() {
    local -a _names=()
    local -A _seen=()
    local _savedIFS="$IFS" _entry
    IFS=';' read -ra _allRepos <<< "$SHADER_REPOS"
    IFS="$_savedIFS"
    for _entry in "${_allRepos[@]}"; do
        parseShaderRepoEntry "$_entry"
        [[ -z $_shaderRepoName ]] && continue
        [[ -n ${_seen["$_shaderRepoName"]+x} ]] && continue
        _seen["$_shaderRepoName"]=1
        _names+=("$_shaderRepoName")
    done
    local IFS=','
    printf '%s\n' "${_names[*]}"
}

# Build (or rebuild) a per-game shader directory containing only the selected repos.
# Creates $MAIN_PATH/game-shaders/<gameKey>/Merged/{Shaders,Textures}/.
# $1: game key  $2: comma-separated selected repo names
function buildGameShaderDir() {
    local _gameKey="$1" _selectedRepos="$2"
    [[ -z $_gameKey ]] && return 1
    local _gameShaderDir="$MAIN_PATH/game-shaders/$_gameKey"
    rm -rf "$_gameShaderDir"
    mkdir -p "$_gameShaderDir/Merged/Shaders" "$_gameShaderDir/Merged/Textures"
    local _outBase="$_gameShaderDir/Merged" _entry _selectedCount=0 _currentIndex=0
    local -A _seen=()

    IFS=';' read -ra _allRepos <<< "$SHADER_REPOS"
    for _entry in "${_allRepos[@]}"; do
        parseShaderRepoEntry "$_entry"
        [[ -z $_shaderRepoName ]] && continue
        [[ -n ${_seen["$_shaderRepoName"]+x} ]] && continue
        _seen["$_shaderRepoName"]=1
        [[ ",$_selectedRepos," != *",$_shaderRepoName,"* ]] && continue
        [[ ! -d "$MAIN_PATH/ReShade_shaders/$_shaderRepoName" ]] && continue
        _selectedCount=$((_selectedCount + 1))
    done

    _seen=()
    for _entry in "${_allRepos[@]}"; do
        parseShaderRepoEntry "$_entry"
        [[ -z $_shaderRepoName ]] && continue
        [[ -n ${_seen["$_shaderRepoName"]+x} ]] && continue
        _seen["$_shaderRepoName"]=1
        [[ ",$_selectedRepos," != *",$_shaderRepoName,"* ]] && continue
        [[ ! -d "$MAIN_PATH/ReShade_shaders/$_shaderRepoName" ]] && continue
        _currentIndex=$((_currentIndex + 1))
        setProgressText "Building shader directory\n[$_currentIndex/$_selectedCount] Merging $_shaderRepoName"
        printf '%b[%d/%d] Merging shader repo:%b %s\n' \
            "$_CYN$_B" "$_currentIndex" "$_selectedCount" "$_R" "$_shaderRepoName"
        mergeShaderDirsTo "ReShade_shaders" "$_shaderRepoName" "$_outBase"
    done
    if [[ -d "$MAIN_PATH/External_shaders" ]]; then
        setProgressText "Building shader directory\n[extra] Merging external shaders"
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
}

# Clone and update selected shader repositories with error tracking.
# $1: comma-separated list of selected repo names
# Returns: 0 if all repos successful, 1 if any repo failed
# Sets _failedRepos to comma-separated list of failed repo names
function ensureSelectedShaderRepos() {
    local _selectedRepos="$1"
    [[ -z $_selectedRepos ]] && return 0
    local _entry _status
    local -A _seen=()
    _failedRepos=""
    IFS=';' read -ra _allRepos <<< "$SHADER_REPOS"
    for _entry in "${_allRepos[@]}"; do
        parseShaderRepoEntry "$_entry"
        [[ -z $_shaderRepoName ]] && continue
        [[ -n ${_seen["$_shaderRepoName"]+x} ]] && continue
        _seen["$_shaderRepoName"]=1
        [[ ",$_selectedRepos," != *",$_shaderRepoName,"* ]] && continue
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
    done
    [[ -n $_failedRepos ]] && return 1
    return 0
}

# Create a per-game ReShade.ini if one does not already exist.
# Default configs use relative shader paths so every game stays self-contained.
# $1: game path
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

# Copy a preset into the game directory if requested and not already present.
# The copy stays per-game and can be customized independently afterwards.
# $1: game path
function ensureGamePreset() {
    local _gamePath="$1"
    [[ -z $LINK_PRESET ]] && return 0
    [[ -f "$MAIN_PATH/$LINK_PRESET" ]] || return 0
    [[ -f "$_gamePath/$LINK_PRESET" ]] && return 0
    cp "$MAIN_PATH/$LINK_PRESET" "$_gamePath/$LINK_PRESET"
}

# Show a shader repository selection dialog.
# $1: comma-separated currently-selected repo names
# Prints comma-separated selected repo names to stdout.
# Returns 1 if the user cancelled.
# SHADER_REPOS format: URL|localname[|branch[|Short description]]
# The 4th field (description) is shown in the UI; it falls back to the URL when absent.
function selectShaders() {
    local _current="$1"
    local -a _names=() _uris=() _descs=() _rows=()
    local -A _seen=()
    local _savedIFS="$IFS"
    IFS=';' read -ra _allRepos <<< "$SHADER_REPOS"
    IFS="$_savedIFS"
    local _entry _checked
    for _entry in "${_allRepos[@]}"; do
        parseShaderRepoEntry "$_entry"
        [[ -z $_shaderRepoName ]] && continue
        [[ -n ${_seen["$_shaderRepoName"]+x} ]] && continue
        _seen["$_shaderRepoName"]=1
        _checked="$(repoChecklistState "$_current" "$_shaderRepoName")"
        _names+=("$_shaderRepoName")
        _uris+=("$_shaderRepoUri")
        _descs+=("$_shaderRepoDesc")
        _rows+=("$_shaderRepoName" "$_shaderRepoDesc" "$_checked")
    done
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
            "Select which shader repositories to install for this game. Unticking a repo removes its shaders from this game." \
            "$_box_h" 100 "$_list_h" "${_rows[@]}") || return 1
        _result=${_result//\"/}
        IFS=' ' read -ra _selected_names <<< "$_result"
    else
        printf '%bSelect shader repositories to install for this game:%b\n' "$_CYN" "$_R"
        local _i _ans
        for (( _i=0; _i<${#_names[@]}; _i++ )); do
            local _def="y"
            [[ "${_rows[$(( (_i * 3) + 2 ))]}" == "OFF" ]] && _def="n"
            printf '  [%s] %s - %s\n     Include? [%s]: ' \
                "$(( _i + 1 ))" "${_names[$_i]}" "${_descs[$_i]}" "$_def"
            read -r _ans
            [[ -z $_ans ]] && _ans="$_def"
            [[ "$_ans" =~ ^(y|Y|yes|YES)$ ]] && _selected_names+=("${_names[$_i]}")
        done
    fi
    local IFS=','
    echo "${_selected_names[*]}"
}

# Like linkShaderFiles but writes into an arbitrary output base directory.
# $1: source directory (full path)
# $2: subdirectory name (Shaders or Textures[/subpath])
# $3: output base directory — files go into $3/$2/
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

# Like mergeShaderDirs but writes into an arbitrary output base directory.
# $1: ReShade_shaders | External_shaders
# $2: repo name (only for ReShade_shaders)
# $3: output base directory (Shaders/ and Textures/ will be created inside it)
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
