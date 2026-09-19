# shellcheck shell=bash
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck disable=SC2154  # _shaderRepo* are set by parseShaderRepoEntry in shader_registry.sh

# Per-game shader directory construction: merging and linking installed repos.

# Rebuild a per-game shader directory from the selected repos.
function buildGameShaderDir() {
    local _gameKey="$1" _selectedRepos="$2" _appId="${3:-}"
    [[ -z $_gameKey ]] && return 1
    logDebug "buildGameShaderDir start gameKey=$_gameKey appId=${_appId:-<none>} repos=${_selectedRepos:-<none>}"
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
    exposeNestedShaderHeadersToRoot "$_outBase"
    mirrorShaderHeadersToMergedRoot "$_outBase"
    removeExcludedShaderEffectsFromBuild "$_outBase" "$_appId"
    logDebug "buildGameShaderDir finish gameKey=$_gameKey"
}

# Detach the ReShade_shaders entry from a game directory. A symlink is only
# unlinked. A real directory (manual install or an old layout) may hold the user's
# own shaders, so it is moved aside to ReShade_shaders.bak-<timestamp> and never
# deleted or overwritten.
function detachGameShaderDir() {
    local _target="$1/ReShade_shaders" _backup

    if [[ -L $_target ]]; then
        unlink "$_target"
    elif [[ -d $_target ]]; then
        _backup="$_target.bak-$(date +%Y%m%d-%H%M%S)"
        while [[ -e $_backup ]]; do
            _backup+="_"
        done
        mv "$_target" "$_backup" || printErr "Could not move '$_target' aside."
        printf '%bKept your existing ReShade_shaders directory as:%b %s\n' "$_YLW" "$_R" "$_backup"
    fi
}

function removeExcludedShaderEffectsFromBuild() {
    local _outBase="$1" _appId="$2"
    local _effect _removed=0

    [[ -n $_appId ]] || return 0

    while IFS= read -r _effect || [[ -n $_effect ]]; do
        [[ -n $_effect ]] || continue
        if [[ -L "$_outBase/Shaders/$_effect" || -f "$_outBase/Shaders/$_effect" ]]; then
            rm -f "$_outBase/Shaders/$_effect"
            _removed=1
            printf '%bSkipping known incompatible effect for AppID %s:%b %s\n' \
                "$_YLW" "$_appId" "$_R" "$_effect"
        fi
    done < <(listExcludedShaderEffectsForApp "$_appId")

    [[ $_removed -eq 0 ]] || logDebug "Removed excluded effects for appId=$_appId"
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

# Link nested .fxh headers up to the top of the merged Shaders directory.
function exposeNestedShaderHeadersToRoot() {
    local _outBase="$1"
    local _shadersDir="$_outBase/Shaders"
    local _file _basename

    [[ -d $_shadersDir ]] || return
    while IFS= read -r -d '' _file; do
        _basename="${_file##*/}"
        [[ -e "$_shadersDir/$_basename" || -L "$_shadersDir/$_basename" ]] && continue
        ln -s "$(realpath "$_file")" "$_shadersDir/$_basename"
    done < <(find "$_shadersDir" -mindepth 2 \( -type f -o -type l \) -name '*.fxh' -print0)
}

# Mirror top-level .fxh headers into the merged root so relative includes resolve.
function mirrorShaderHeadersToMergedRoot() {
    local _outBase="$1"
    local _shadersDir="$_outBase/Shaders"
    local _file _basename

    [[ -d $_shadersDir ]] || return
    while IFS= read -r -d '' _file; do
        _basename="${_file##*/}"
        [[ -e "$_outBase/$_basename" || -L "$_outBase/$_basename" ]] && continue
        ln -s "$(realpath "$_file")" "$_outBase/$_basename"
    done < <(find "$_shadersDir" -maxdepth 1 \( -type f -o -type l \) -name '*.fxh' -print0)
}

# Merge shader directories into an arbitrary output base directory.
function mergeShaderDirsTo() {
    [[ $1 != ReShade_shaders && $1 != External_shaders ]] && return
    local _outBase="$3"
    local _repoRoot="" dirPath dirName anyDir

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
