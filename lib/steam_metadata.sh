# shellcheck shell=bash

# Find Steam's binary appinfo.vdf, which contains authoritative launch exe data.
function findSteamAppinfoVdf() {
    local _root
    while IFS= read -r _root; do
        [[ -f "$_root/appcache/appinfo.vdf" ]] && { printf '%s\n' "$_root/appcache/appinfo.vdf"; return; }
    done < <(listSteamRoots)
}

# Parse Steam's binary appinfo.vdf once and emit one line per game.
function loadSteamAppinfoExes() {
    local _appinfo="$1"
    [[ -f $_appinfo ]] || return
    command -v python3 &>/dev/null || return
    python3 - "$_appinfo" 2>/dev/null <<'PYEOF'
import sys, struct
try:
    with open(sys.argv[1], 'rb') as fh:
        raw = fh.read()
except OSError:
    sys.exit(0)

magic = raw[:4]
if len(raw) < 8 or magic[1:4] != b'DV\x07':
    sys.exit(0)

pos = 8 if magic[0] < 0x29 else 16
new_sha = magic[0] >= 0x28
EXEC_PAT = b'\x01\xc9\x01\x00\x00'
META_SZ = 4 + 4 + 8 + 20 + 4 + (20 if new_sha else 0)

while pos + 8 <= len(raw):
    appid = struct.unpack_from('<I', raw, pos)[0]; pos += 4
    if appid == 0:
        break
    sz = struct.unpack_from('<I', raw, pos)[0]; pos += 4
    end = pos + sz
    chunk = raw[pos + META_SZ:end]
    pos = end

    seen, results = set(), []
    p = 0
    while len(results) < 8:
        i = chunk.find(EXEC_PAT, p)
        if i == -1:
            break
        s = i + len(EXEC_PAT)
        e = chunk.find(b'\x00', s)
        if e == -1:
            break
        exe = chunk[s:e].decode('utf-8', 'replace').replace('\\\\', '/').replace('\\', '/')
        if exe.lower().endswith('.exe'):
            key = exe.lower()
            if key not in seen:
                seen.add(key)
                results.append(exe.replace('|', '/'))
        p = i + 1

    if results:
        print(f"{appid}:{'|'.join(results)}")
PYEOF
}

# Detect the architecture and best ReShade DLL hook for a game directory.
function detectExeInfo() {
    local _dir="$1"
    command -v python3 &>/dev/null || return 1
    python3 - "$_dir" 2>/dev/null <<'PYEOF'
import sys, struct, os, re
BLACKLIST = re.compile(r'crash|setup|uninst|install|redist|vcredist|dxsetup|vc_redist|dotnet|error|remov', re.I)
PRIORITY = ['d3d12.dll','d3d11.dll','d3d10.dll','d3d9.dll','d3d8.dll','opengl32.dll','ddraw.dll','dinput8.dll']
OVERRIDE = {'d3d12.dll':'dxgi','d3d11.dll':'dxgi','d3d10.dll':'dxgi','d3d9.dll':'d3d9','d3d8.dll':'d3d8','opengl32.dll':'opengl32','ddraw.dll':'ddraw','dinput8.dll':'dinput8'}

def parse_pe(path):
    try:
        with open(path, 'rb') as f:
            data = f.read(min(os.path.getsize(path), 2 * 1024 * 1024))
    except OSError:
        return None, []
    if data[:2] != b'MZ':
        return None, []
    e_lfanew = struct.unpack_from('<I', data, 60)[0]
    if e_lfanew + 24 > len(data) or data[e_lfanew:e_lfanew+4] != b'PE\x00\x00':
        return None, []
    num_sec = struct.unpack_from('<H', data, e_lfanew + 6)[0]
    opt_sz = struct.unpack_from('<H', data, e_lfanew + 20)[0]
    opt_off = e_lfanew + 24
    if opt_off + 2 > len(data):
        return None, []
    opt_magic = struct.unpack_from('<H', data, opt_off)[0]
    is64 = (opt_magic == 0x20b)
    arch = 64 if is64 else 32
    imp_rva_off = opt_off + (120 if is64 else 104)
    if imp_rva_off + 4 > len(data):
        return arch, []
    imp_rva = struct.unpack_from('<I', data, imp_rva_off)[0]
    if imp_rva == 0:
        return arch, []
    sec_off = opt_off + opt_sz
    sections = []
    for i in range(num_sec):
        s = sec_off + i * 40
        if s + 40 > len(data):
            break
        va = struct.unpack_from('<I', data, s + 12)[0]
        vsz = struct.unpack_from('<I', data, s + 16)[0]
        raw = struct.unpack_from('<I', data, s + 20)[0]
        sections.append((va, vsz, raw))
    def rva2off(rva):
        for va, vsz, raw in sections:
            if va <= rva < va + vsz:
                return raw + (rva - va)
        return None
    imp_off = rva2off(imp_rva)
    if imp_off is None:
        return arch, []
    imports = []
    idx = 0
    while True:
        d = imp_off + idx * 20
        if d + 20 > len(data):
            break
        name_rva = struct.unpack_from('<I', data, d + 12)[0]
        if name_rva == 0:
            break
        no = rva2off(name_rva)
        if no is None:
            break
        end = data.find(b'\x00', no)
        if end < 0:
            break
        imports.append(data[no:end].decode('ascii', 'replace').lower())
        idx += 1
    return arch, imports

game_dir = sys.argv[1] if len(sys.argv) > 1 else '.'
try:
    exes = [f for f in os.listdir(game_dir) if f.lower().endswith('.exe') and not BLACKLIST.search(f)]
except OSError:
    sys.exit(1)

arch_votes = {32: 0, 64: 0}
dll_votes = {}
for exe in exes:
    arch, imports = parse_pe(os.path.join(game_dir, exe))
    if arch:
        arch_votes[arch] += 1
    for imp in imports:
        if imp in OVERRIDE:
            dll_votes[imp] = dll_votes.get(imp, 0) + 1

final_arch = 64 if arch_votes[64] >= arch_votes[32] else 32
best_dll = next((OVERRIDE[p] for p in PRIORITY if p in dll_votes), None)
if best_dll is None:
    best_dll = 'dxgi' if final_arch == 64 else 'd3d9'
print(f"arch={final_arch}")
print(f"dll={best_dll}")
PYEOF
}

function _trimSteamMetadataField() {
    local _value="$1"
    _value=${_value//$'\r'/}
    _value="${_value#"${_value%%[![:space:]]*}"}"
    _value="${_value%"${_value##*[![:space:]]}"}"
    printf '%s\n' "$_value"
}

function _upsertDetectedSteamGame() {
    local _appId="$1" _name="$2" _path="$3" _exe="$4" _icon="$5" _reason="$6"
    local -n _bestIdxByPathMap="$7"
    local -n _bestIdxByAppIdMap="$8"
    local _dedupeKey _oldIdx _newScore _oldScore _oldPathKey _idx

    _dedupeKey=${_path,,}
    if [[ -n ${_bestIdxByAppIdMap["$_appId"]+x} ]]; then
        _oldIdx=${_bestIdxByAppIdMap["$_appId"]}
        _newScore=$(scoreExeCandidate "$_path" "$_exe")
        _oldScore=$(scoreExeCandidate "${DETECTED_GAME_PATHS[_oldIdx]}" "${DETECTED_GAME_EXES[_oldIdx]}")
        if (( _newScore > _oldScore )); then
            _oldPathKey="${DETECTED_GAME_PATHS[_oldIdx],,}"
            DETECTED_GAME_NAMES[_oldIdx]="$_name"
            DETECTED_GAME_APPIDS[_oldIdx]="$_appId"
            DETECTED_GAME_PATHS[_oldIdx]="$_path"
            DETECTED_GAME_EXES[_oldIdx]="$_exe"
            DETECTED_GAME_ICONS[_oldIdx]="$_icon"
            DETECTED_GAME_REASONS[_oldIdx]="$_reason"
            [[ -n ${_bestIdxByPathMap["$_oldPathKey"]+x} ]] && unset "_bestIdxByPathMap[$_oldPathKey]"
            _bestIdxByPathMap["$_dedupeKey"]=$_oldIdx
        fi
        return
    fi

    if [[ -n ${_bestIdxByPathMap["$_dedupeKey"]+x} ]]; then
        _oldIdx=${_bestIdxByPathMap["$_dedupeKey"]}
        _newScore=$(scoreExeCandidate "$_path" "$_exe")
        _oldScore=$(scoreExeCandidate "$_path" "${DETECTED_GAME_EXES[_oldIdx]}")
        if (( _newScore > _oldScore )); then
            DETECTED_GAME_NAMES[_oldIdx]="$_name"
            DETECTED_GAME_APPIDS[_oldIdx]="$_appId"
            DETECTED_GAME_PATHS[_oldIdx]="$_path"
            DETECTED_GAME_EXES[_oldIdx]="$_exe"
            DETECTED_GAME_ICONS[_oldIdx]="$_icon"
            DETECTED_GAME_REASONS[_oldIdx]="$_reason"
        fi
        return
    fi

    DETECTED_GAME_NAMES+=("$_name")
    DETECTED_GAME_APPIDS+=("$_appId")
    DETECTED_GAME_PATHS+=("$_path")
    DETECTED_GAME_EXES+=("$_exe")
    DETECTED_GAME_ICONS+=("$_icon")
    DETECTED_GAME_REASONS+=("$_reason")
    _idx=$((${#DETECTED_GAME_PATHS[@]} - 1))
    _bestIdxByPathMap["$_dedupeKey"]=$_idx
    _bestIdxByAppIdMap["$_appId"]=$_idx
}

function _processSteamManifest() {
    local _manifest="$1" _steamapps="$2" _steamRoot="$3"
    local _appinfoExesName="$4" _bestIdxByPathName="$5" _bestIdxByAppIdName="$6"
    local -n _appinfoExesMap="$_appinfoExesName"
    local -n _bestIdxByPathMap="$_bestIdxByPathName"
    local -n _bestIdxByAppIdMap="$_bestIdxByAppIdName"
    local _appId _name _installDir _type _root _resolved _path _reason _exe _icon _aiCand
    local -a _aiCands

    _appId=$(grep -m1 -o '"appid"[[:space:]]*"[0-9]*"' "$_manifest" | grep -o '[0-9]*')
    _name=$(grep -m1 -o '"name"[[:space:]]*"[^"]*"' "$_manifest" | sed -E 's/.*"name"[[:space:]]*"([^"]*)".*/\1/')
    _installDir=$(grep -m1 -o '"installdir"[[:space:]]*"[^"]*"' "$_manifest" | sed -E 's/.*"installdir"[[:space:]]*"([^"]*)".*/\1/')
    _type=$(grep -m1 -o '"type"[[:space:]]*"[^"]*"' "$_manifest" | sed -E 's/.*"type"[[:space:]]*"([^"]*)".*/\1/' | tr '[:upper:]' '[:lower:]')

    _appId=$(_trimSteamMetadataField "$_appId")
    _name=$(_trimSteamMetadataField "$_name")
    _installDir=$(_trimSteamMetadataField "$_installDir")
    _type=$(_trimSteamMetadataField "$_type")

    [[ -n $_appId && -n $_installDir ]] || return
    [[ -n $_type && $_type != "game" ]] && return
    [[ $_name =~ ^Proton([[:space:]]|$) || $_name =~ ^Steam[[:space:]]Linux[[:space:]]Runtime || $_name == "Steamworks Common Redistributables" ]] && return

    _root="$_steamapps/common/$_installDir"
    [[ -d $_root ]] || return
    _resolved=$(resolveGameInstallDir "$_root" "$_appId")
    _path=${_resolved%%|*}
    _reason=${_resolved#*|}
    _exe=""

    if [[ $_reason != preset:* && $_reason != builtin:* && -n ${_appinfoExesMap[$_appId]+x} ]]; then
        IFS='|' read -ra _aiCands <<< "${_appinfoExesMap[$_appId]}"
        for _aiCand in "${_aiCands[@]}"; do
            if [[ -f "$_root/$_aiCand" ]]; then
                _path=$(dirname "$_root/$_aiCand")
                _exe=$(basename "$_aiCand")
                _reason="appinfo"
                break
            fi
        done
    fi

    [[ -z $_exe ]] && _exe=$(pickBestExeInDir "$_path")
    _path=$(realpath "$_path" 2>/dev/null || printf '%s' "$_path")
    _path=${_path%/}

    [[ -d $_path ]] || return
    [[ -z $_name ]] && _name="AppID $_appId"
    [[ -z $_exe ]] && return
    _icon=$(findSteamIconPath "$_steamRoot" "$_appId" 2>/dev/null || echo "")

    _upsertDetectedSteamGame "$_appId" "$_name" "$_path" "$_exe" "$_icon" "$_reason" "$_bestIdxByPathName" "$_bestIdxByAppIdName"
}

# Fill auto-detected Steam game arrays.
function detectSteamGames() {
    DETECTED_GAME_NAMES=()
    DETECTED_GAME_APPIDS=()
    DETECTED_GAME_PATHS=()
    DETECTED_GAME_EXES=()
    DETECTED_GAME_ICONS=()
    DETECTED_GAME_REASONS=()
    local _steamapps _manifest _steamRoot
    local -A _bestIdxByPath=()
    local -A _bestIdxByAppId=()
    local -A _appinfoExes=()
    local _appinfoFile

    _appinfoFile=$(findSteamAppinfoVdf)
    if [[ -n $_appinfoFile ]]; then
        while IFS=: read -r _aid _aexes; do
            [[ -n $_aid && -n $_aexes ]] && _appinfoExes["$_aid"]="$_aexes"
        done < <(loadSteamAppinfoExes "$_appinfoFile")
    fi

    while IFS= read -r _steamapps; do
        [[ -d $_steamapps ]] || continue
        _steamRoot="${_steamapps%/steamapps}"
        [[ -d $_steamRoot ]] || continue

        for _manifest in "$_steamapps"/appmanifest_*.acf; do
            [[ -f $_manifest ]] || continue
            _processSteamManifest "$_manifest" "$_steamapps" "$_steamRoot" _appinfoExes _bestIdxByPath _bestIdxByAppId
        done
    done < <(listSteamAppsDirs)
}