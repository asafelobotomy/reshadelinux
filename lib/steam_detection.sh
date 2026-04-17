# shellcheck shell=bash

# Return all known Steam roots, deduplicated across symlinked paths.
function listSteamRoots() {
    local _root _key
    local -A _seen=()

    for _root in \
        "${XDG_DATA_HOME:-$HOME/.local/share}/Steam" \
        "$HOME/.local/share/Steam" \
        "$HOME/.steam/steam" \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
        _key=$(realpath "$_root" 2>/dev/null || printf '%s' "$_root")
        [[ -n ${_seen["$_key"]+x} ]] && continue
        _seen["$_key"]=1
        printf '%s\n' "$_root"
    done
}

# Return all detected Steam library steamapps directories (one per line).
function listSteamAppsDirs() {
    local _root _vdf _libPath _key
    local -A _seen=()

    while IFS= read -r _root; do
        [[ -d "$_root/steamapps" ]] || continue
        _key=$(realpath "$_root/steamapps" 2>/dev/null || printf '%s' "$_root/steamapps")
        if [[ -z ${_seen["$_key"]+x} ]]; then
            printf '%s\n' "$_root/steamapps"
            _seen["$_key"]=1
        fi
        _vdf="$_root/steamapps/libraryfolders.vdf"
        [[ -f $_vdf ]] || continue
        while IFS= read -r _libPath; do
            _libPath=${_libPath//\\\\/\\}
            [[ -d "$_libPath/steamapps" ]] || continue
            _key=$(realpath "$_libPath/steamapps" 2>/dev/null || printf '%s' "$_libPath/steamapps")
            if [[ -z ${_seen["$_key"]+x} ]]; then
                printf '%s\n' "$_libPath/steamapps"
                _seen["$_key"]=1
            fi
        done < <(sed -n 's/.*"path"[[:space:]]*"\([^"]*\)".*/\1/p' "$_vdf")
    done < <(listSteamRoots)
}

# Find a locally cached Steam icon for an AppID.
function findSteamIconPath() {
    local _steamRoot="$1" _appId="$2" _root _dir _f _c
    local _cacheDir="${XDG_CACHE_HOME:-$HOME/.cache}/reshadelinux/icons"

    if [[ $_steamRoot =~ ^[0-9]+$ ]] && [[ -n $_appId && $_appId == /* ]]; then
        local _tmp="$_steamRoot"
        _steamRoot="$_appId"
        _appId="$_tmp"
    fi

    for _c in "$_cacheDir/${_appId}.png" "$_cacheDir/${_appId}.jpg"; do
        [[ -f $_c ]] && { printf '%s\n' "$_c"; return; }
    done

    if [[ -n $_steamRoot && -d $_steamRoot ]]; then
        _dir="$_steamRoot/appcache/librarycache/${_appId}"
        if [[ -d $_dir ]]; then
            [[ -f "$_dir/logo.png" ]] && { printf '%s\n' "$_dir/logo.png"; return; }
            for _f in "$_dir"/*.jpg; do
                [[ -f $_f ]] || continue
                case $(basename "$_f") in header.jpg|library_*.jpg) continue ;; esac
                printf '%s\n' "$_f"
                return
            done
            [[ -f "$_dir/header.jpg" ]] && { printf '%s\n' "$_dir/header.jpg"; return; }
        fi
    fi

    while IFS= read -r _root; do
        _dir="$_root/appcache/librarycache/${_appId}"
        [[ -d $_dir ]] || continue
        [[ -f "$_dir/logo.png" ]] && { printf '%s\n' "$_dir/logo.png"; return; }
        for _f in "$_dir"/*.jpg; do
            [[ -f $_f ]] || continue
            case $(basename "$_f") in header.jpg|library_*.jpg) continue ;; esac
            printf '%s\n' "$_f"
            return
        done
        [[ -f "$_dir/header.jpg" ]] && { printf '%s\n' "$_dir/header.jpg"; return; }
    done < <(listSteamRoots)
}

# Return preset subdirectory for an AppID from BUILTIN_GAME_DIR_PRESETS.
function getBuiltInGameDirPreset() {
    local _appId="$1" _entry _k _v
    local IFS=';'
    for _entry in $BUILTIN_GAME_DIR_PRESETS; do
        _k=${_entry%%|*}
        _v=${_entry#*|}
        [[ $_k == "$_appId" ]] && { printf '%s\n' "$_v"; return; }
    done
}

# Pick the most likely game executable from a directory.
function pickBestExeInDir() {
    local _dir="$1" _exe _name _score _best="" _bestScore=-999999

    for _exe in "$_dir"/*.exe; do
        [[ -f $_exe ]] || continue
        _name=${_exe##*/}
        _score=$(scoreExeCandidate "$_dir" "$_name")
        if [[ $_score -gt $_bestScore ]]; then
            _bestScore=$_score
            _best=$_name
        fi
    done

    [[ $_bestScore -le 0 ]] && _best=""
    printf '%s\n' "$_best"
}

# Score a specific executable candidate for a directory using the same heuristics.
function scoreExeCandidate() {
    local _dir="$1" _name="$2" _lname _parentDir _score=50
    [[ -z $_name ]] && { printf '%s\n' "-999999"; return; }
    _lname=${_name,,}
    _parentDir=$(basename "$_dir" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')

    [[ $_lname =~ (unityplayer|unitycrash|crashhandler|easyanticheat|battleye|asp|unins|uninstall|setup|installer|vcredist|redist|eac|crashreport|crashpad|benchmark|test|launcher|update|check|remov|error|consultant) ]] && _score=$((_score - 200))
    [[ $_lname =~ ^mono\. ]] && _score=$((_score - 200))
    [[ $_lname =~ debug ]] && _score=$((_score - 80))
    [[ "$_lname" == *"${_parentDir}"* ]] && _score=$((_score + 150))
    [[ $_lname =~ (game|main|app|engine|client|server|game_?setup) ]] && _score=$((_score + 80))
    [[ $_lname =~ (win64|x64|win32|i386|64|x86|ia32) ]] && _score=$((_score + 40))
    [[ $_lname =~ ^[a-z][a-z0-9]?$ || $_lname == "app.exe" ]] && _score=$((_score - 30))

    printf '%s\n' "$_score"
}

# Resolve the preferred install directory for a Steam game root.
function resolveGameInstallDir() {
    local _root="$1" _appId="$2"
    local _preset _entry _k _v _candidate _exe _depth _score _best="" _bestScore=-999999 _name

    if [[ -n ${GAME_DIR_PRESETS:-} ]]; then
        local IFS=';'
        for _entry in $GAME_DIR_PRESETS; do
            _k=${_entry%%|*}
            _v=${_entry#*|}
            if [[ $_k == "$_appId" ]] && [[ -n $_v ]] && [[ -d "$_root/$_v" ]]; then
                printf '%s|%s\n' "$_root/$_v" "preset:$_v"
                return
            fi
        done
    fi

    _preset=$(getBuiltInGameDirPreset "$_appId")
    if [[ -n $_preset ]] && [[ -d "$_root/$_preset" ]]; then
        printf '%s|%s\n' "$_root/$_preset" "builtin:$_preset"
        return
    fi

    for _candidate in \
        "Binaries/Win64" "Binaries/Win32" "Binaries" \
        "bin/x64" "bin/x86" "bin" \
        "Win64" "Win32" "x64" "x86" "."; do
        if [[ $_candidate == "." ]]; then
            _candidate="$_root"
        else
            _candidate="$_root/$_candidate"
        fi
        if [[ -d $_candidate ]] && compgen -G "$_candidate/*.exe" &>/dev/null; then
            printf '%s|%s\n' "$_candidate" "heuristic"
            return
        fi
    done

    while IFS='|' read -r _depth _exe; do
        [[ -n $_exe ]] || continue
        _score=$((200 - _depth * 12))
        _name=${_exe##*/}
        _name=${_name,,}
        [[ $_name =~ (unins|uninstall|setup|installer|vcredist|redist|eac|easyanticheat|crashreport|crashpad|benchmark|remov|error|consultant) ]] && _score=$((_score - 100))
        [[ $_name =~ ^mono\. ]] && _score=$((_score - 100))
        [[ $_name =~ debug ]] && _score=$((_score - 50))
        [[ $_exe == */Mono/lib/* || $_exe == */Mono/bin/* || $_exe == */MonoBleedingEdge/* ]] && _score=$((_score - 300))
        [[ $_name =~ (shipping|game|win64|x64) ]] && _score=$((_score + 15))
        if [[ $_score -gt $_bestScore ]]; then
            _bestScore=$_score
            _best=$(dirname "$_exe")
        fi
    done < <(find "$_root" -maxdepth 5 -type f -iname '*.exe' -printf '%d|%p\n' 2>/dev/null)

    if [[ -n $_best && $_bestScore -ge 0 ]]; then
        printf '%s|%s\n' "$_best" "scan"
    else
        printf '%s|%s\n' "$_root" "root"
    fi
}