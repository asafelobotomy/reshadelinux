#!/bin/bash
# Test utilities and function definitions for reshade-linux automated testing
# This file extracts the core functions needed for testing without running the main install logic

# Requires: BUILTIN_GAME_DIR_PRESETS variable to be set

# ============================================================================
# CORE DETECTION FUNCTIONS (extracted from reshade-linux.sh)
# ============================================================================

# Pick the most likely game executable from a directory.
# ReShade requires the ACTUAL game executable for DLL injection (via WINEDLLOVERRIDES).
# Filters out utilities (crash handlers, installers, etc.) and scores by name similarity to parent folder.
# Prints basename (or empty string if none found).
function pickBestExeInDir() {
    local _dir="$1" _parentDir _exe _name _lname _score _best="" _bestScore=-999999 _isUtility
    local _exeList=()
    
    _parentDir=$(basename "$_dir" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
    
    # Collect all .exe files and score them.
    for _exe in "$_dir"/*.exe; do
        [[ -f $_exe ]] || continue
        _name=${_exe##*/}
        _lname=${_name,,}
        _score=50
        _isUtility=0
        
        # Aggressive blacklist: filter OUT known non-game executables.
        if [[ $_lname =~ (unityplayer|unitycrash|crashhandler|easyanticheat|battleye|asp|unins|uninstall|setup|installer|vcredist|redist|eac|crashreport|benchmark|test|launcher|update|check) ]]; then
            _isUtility=1
            _score=$((_score - 200))
        fi
        
        # Strong positive: name contains parent directory name.
        [[ "$_lname" == *"${_parentDir}"* ]] && _score=$((_score + 150))
        
        # Moderate positive: contains game-like keywords.
        [[ $_lname =~ (game|main|app|engine|client|server|game_?setup) ]] && _score=$((_score + 80))
        
        # Moderate positive: contains architecture keywords (games tend to match their arch).
        [[ $_lname =~ (win64|x64|win32|i386|64|x86|ia32) ]] && _score=$((_score + 40))
        
        # Small penalty: generic names that could be utilities.
        [[ $_lname =~ ^[a-z][a-z0-9]?$ || $_lname == "app.exe" ]] && _score=$((_score - 30))
        
        if [[ $_score -gt $_bestScore ]]; then
            _bestScore=$_score
            _best=$_name
        fi
    done
    
    printf '%s\n' "$_best"
}

# Find a Steam game icon file.
# Returns path to icon file using 3-tier lookup priority:
#   1. Persistent cache (~/.cache/reshade-linux/icons/)
#   2. Local Steam cache (logo.png, hash-named jpg files, header.jpg)
#   3. Empty string if none found
function findSteamIconPath() {
    local _steamRoot="$1" _appId="$2"
    local _cacheDir="${XDG_CACHE_HOME:-$HOME/.cache}/reshade-linux/icons"
    local _libDir="$_steamRoot/appcache/librarycache/$_appId"
    local _file
    
    # Tier 1: Persistent cache (fastest)
    if [[ -d "$_cacheDir" ]]; then
        for _file in "$_cacheDir"/"$_appId".*; do
            [[ -f "$_file" ]] && { printf '%s\n' "$_file"; return; }
        done
    fi
    
    # Tier 2: Local Steam cache
    if [[ -d "$_libDir" ]]; then
        # Try logo.png first
        [[ -f "$_libDir/logo.png" ]] && { printf '%s\n' "$_libDir/logo.png"; return; }
        
        # Try hash-named jpg files (actual game icons, not banners)
        for _file in "$_libDir"/*.jpg; do
            [[ -f "$_file" ]] || continue
            basename "$_file" | grep -qE "^[a-f0-9]{40}\.jpg$" && \
                ! grep -q "library" <<< "$(basename "$_file")" && \
                { printf '%s\n' "$_file"; return; }
        done
        
        # Fall through to header.jpg
        [[ -f "$_libDir/header.jpg" ]] && { printf '%s\n' "$_libDir/header.jpg"; return; }
    fi
}

# Return preset subdirectory for an AppID from BUILTIN_GAME_DIR_PRESETS.
function getBuiltInGameDirPreset() {
    local _appId="$1" _entry _k _v
    local IFS=";"
    for _entry in $BUILTIN_GAME_DIR_PRESETS; do
        _k=${_entry%%|*}
        _v=${_entry#*|}
        [[ $_k == "$_appId" ]] && { printf '%s\n' "$_v"; return; }
    done
}

# Build a stable per-game install key.
function buildGameInstallKey() {
    local _aid="$1" _gp="$2"
    if [[ -n $_aid ]]; then
        printf '%s\n' "$_aid"
        return
    fi
    [[ -z $_gp ]] && return 1
    printf 'path-%s\n' "$(printf '%s' "$_gp" | sha256sum | cut -c1-16)"
}

# Persist game install state to $MAIN_PATH/game-state/<gameKey>.state.
# $1: gameKey  $2: gamePath  $3: dll  $4: arch  $5: selected_repos (comma-sep)  $6: appId(optional)
function writeGameState() {
    local _gameKey="$1" _gp="$2" _dll="$3" _arch="$4" _repos="$5" _appId="${6:-}"
    [[ -z $_gameKey ]] && return
    local _dir="$MAIN_PATH/game-state"
    mkdir -p "$_dir" 2>/dev/null || return
    printf 'dll=%s\narch=%s\ngamePath=%s\nselected_repos=%s\napp_id=%s\n' \
        "$_dll" "$_arch" "$_gp" "$_repos" "$_appId" > "$_dir/$_gameKey.state"
}

function applyLaunchOption() {
    local _aid="$1" _opt="$2"
    [[ -z $_aid || -z $_opt ]] && return 1
    command -v python3 &>/dev/null || return 1

    local _vcfg _applied=0
    for _vcfg in \
        "$HOME/.local/share/Steam/userdata"/*/config/localconfig.vdf \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/userdata"/*/config/localconfig.vdf; do
        [[ -f $_vcfg ]] || continue
        python3 - "$_vcfg" "$_aid" "$_opt" <<'PYEOF' >/dev/null 2>&1
import re
import shutil
import sys

vdf_path, appid, launch_opt = sys.argv[1], sys.argv[2], sys.argv[3]

with open(vdf_path, encoding="utf-8", errors="replace") as handle:
    text = handle.read()

apps_match = re.search(r'"[Aa]pps"\s*\{', text)
if not apps_match:
    sys.exit(1)

appid_match = re.search(rf'"{re.escape(appid)}"\s*\{{', text[apps_match.end():])
if not appid_match:
    sys.exit(1)

block_start = apps_match.end() + appid_match.end()
depth = 1
block_end = block_start
for offset, char in enumerate(text[block_start:]):
    if char == '{':
        depth += 1
    elif char == '}':
        depth -= 1
        if depth == 0:
            block_end = block_start + offset
            break
else:
    sys.exit(1)

block = text[block_start:block_end]
escaped_launch_opt = launch_opt.replace('\\', '\\\\').replace('"', '\\"')
launch_line = f'"LaunchOptions"\t\t"{escaped_launch_opt}"'
launch_re = re.compile(r'(?im)^(\s*)"LaunchOptions"\s+".*"$')
if launch_re.search(block):
    new_block = launch_re.sub(lambda match: f'{match.group(1)}{launch_line}', block, count=1)
else:
    indent_match = re.search(r'\n(\s+)"', block)
    indent = indent_match.group(1) if indent_match else '\t' * 8
    new_block = block.rstrip() + f'\n{indent}{launch_line}\n'

new_text = text[:block_start] + new_block + text[block_end:]
if new_text == text:
    sys.exit(0)

shutil.copy2(vdf_path, vdf_path + '.reshade.bak')
with open(vdf_path, 'w', encoding='utf-8') as handle:
    handle.write(new_text)
PYEOF
        [[ $? -eq 0 ]] && _applied=1
    done

    [[ $_applied -eq 1 ]]
}

function getDefaultSelectedRepos() {
    local -a _names=()
    local _savedIFS="$IFS" _entry _uri _repoName _branch
    IFS=';' read -ra _allRepos <<< "$SHADER_REPOS"
    IFS="$_savedIFS"
    for _entry in "${_allRepos[@]}"; do
        IFS='|' read -r _uri _repoName _branch <<< "$_entry"
        IFS="$_savedIFS"
        [[ -n $_repoName ]] && _names+=("$_repoName")
    done
    local IFS=','
    printf '%s\n' "${_names[*]}"
}

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

# Like linkShaderFiles but writes into an arbitrary output base directory.
function linkShaderFilesTo() {
    [[ ! -d $1 ]] && return
    local _inDir="$1" _subDir="$2" _outBase="$3"
    cd "$_inDir" || return
    local _outDir="$_outBase/$_subDir"
    mkdir -p "$_outDir"
    local _outDirReal
    _outDirReal="$(realpath "$_outDir")"
    for file in *; do
        [[ ! -f $file ]] && continue
        [[ -L "$_outDirReal/$file" ]] && continue
        ln -s "$(realpath "$_inDir/$file")" "$_outDirReal/"
    done
}

# Like mergeShaderDirs but writes into an arbitrary output base directory.
function mergeShaderDirsTo() {
    [[ $1 != ReShade_shaders && $1 != External_shaders ]] && return
    local _outBase="$3"
    local dirPath
    for dirName in Shaders Textures; do
        [[ $1 == "ReShade_shaders" ]] \
            && dirPath=$(find "$MAIN_PATH/$1/$2" ! -path . -type d -name "$dirName" 2>/dev/null) \
            || dirPath="$MAIN_PATH/$1/$dirName"
        linkShaderFilesTo "$dirPath" "$dirName" "$_outBase"
        while IFS= read -rd '' anyDir; do
            linkShaderFilesTo "$dirPath/$anyDir" "$dirName/$anyDir" "$_outBase"
        done < <(find . ! -path . -type d -print0 2>/dev/null)
    done
}

# Build (or rebuild) a per-game shader directory containing only selected repos.
function buildGameShaderDir() {
    local _gameKey="$1" _selectedRepos="$2"
    [[ -z $_gameKey ]] && return 1
    local _gameShaderDir="$MAIN_PATH/game-shaders/$_gameKey"
    rm -rf "$_gameShaderDir"
    mkdir -p "$_gameShaderDir/Merged/Shaders" "$_gameShaderDir/Merged/Textures"
    local _outBase="$_gameShaderDir/Merged"
    IFS=';' read -ra _allRepos <<< "$SHADER_REPOS"
    for _entry in "${_allRepos[@]}"; do
        IFS='|' read -r _uri _repoName _branch <<< "$_entry"
        [[ -z $_repoName ]] && continue
        [[ ",$_selectedRepos," != *",$_repoName,"* ]] && continue
        [[ ! -d "$MAIN_PATH/ReShade_shaders/$_repoName" ]] && continue
        mergeShaderDirsTo "ReShade_shaders" "$_repoName" "$_outBase"
    done
    if [[ -d "$MAIN_PATH/External_shaders" ]]; then
        mergeShaderDirsTo "External_shaders" "" "$_outBase"
        # Link loose files in External_shaders root (not inside Shaders/ subdirectory).
        cd "$MAIN_PATH/External_shaders" || return
        local _file
        for _file in *; do
            [[ ! -f $_file || -L "$_outBase/Shaders/$_file" ]] && continue
            ln -s "$(realpath "$MAIN_PATH/External_shaders/$_file")" "$_outBase/Shaders/"
        done
    fi
}

function ensureGameIni() {
    local _gamePath="$1"
    [[ ${GLOBAL_INI:-ReShade.ini} == 0 ]] && return 0
    local _target="$_gamePath/ReShade.ini"
    [[ -f $_target ]] && return 0
    if [[ ${GLOBAL_INI:-ReShade.ini} == ReShade.ini ]]; then
        cat > "$_target" <<'EOF'
[GENERAL]
EffectSearchPaths=.\ReShade_shaders\Merged\Shaders
TextureSearchPaths=.\ReShade_shaders\Merged\Textures
EOF
        return 0
    fi
    [[ -f "$MAIN_PATH/${GLOBAL_INI:-ReShade.ini}" ]] || return 1
    cp "$MAIN_PATH/${GLOBAL_INI:-ReShade.ini}" "$_target"
}
