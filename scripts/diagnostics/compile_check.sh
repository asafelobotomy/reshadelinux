#!/usr/bin/env bash
# purpose:  Run the real ReShade under GE-Proton against the merged shader directory of chosen packs and report which effects compile.
# when:     Opt-in, after changing shader merging, search paths, the registry or SHADER_BROKEN_EFFECTS. Needs network, a display (or xvfb-run), about 4 GB of cache and 5-15 minutes for every pack. Do not use it in CI.
# inputs:   Flags: --packs LIST|all, --lab DIR, --software, --include-broken, --timeout SECONDS, --stall SECONDS, --purge, --help.
# outputs:  A summary, one line per failing effect, and COMPILE_CHECK_RESULT=PASS|FAIL|NO_RUNTIME. Exit 0 pass, 1 an effect failed, 2 the check could not run.
# risk:     safe (downloads into its own cache directory, never touches the real workspace or any game; a test window opens while it runs)
# source:   original
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./helpers/common.sh
source "$SCRIPT_DIR/helpers/common.sh"
# shellcheck source=../../lib/install.sh
source "$REPO_DIR/lib/install.sh"

# Pinned like appimagetool: fail closed when a download does not match.
GE_PROTON_TAG="GE-Proton11-7"
GE_PROTON_SHA256="c5448b76a230384e2d7bc6beb5ccb97bafb7e2c3b6c527cb03a1a546bbcb00a0"
LLVM_MINGW_TAG="20260908"
LLVM_MINGW_SHA256="2258c745e3155870c80793f3e8c80b28fbde11b9ff73c4c78783635b3440b092"

LAB="${COMPILE_CHECK_LAB:-${XDG_CACHE_HOME:-$HOME/.cache}/reshadelinux-compile-check}"
PACKS="all"
SOFTWARE=0
INCLUDE_BROKEN=0
TIMEOUT_SECONDS=1800
STALL_SECONDS=180
POLL_SECONDS=5
USE_XVFB=0
PURGE=0
PROTON_PID=""

usage() {
    cat <<'EOF'
Usage: compile_check.sh [options]

Builds the merged shader directory for the chosen packs the way the installer does, runs the
real ReShade 6.x under GE-Proton with a small D3D11 program, and reports which effects compile.

  --packs LIST        comma-separated registry names, or "all" (default)
  --lab DIR           cache directory (default: ~/.cache/reshadelinux-compile-check)
  --software          use the lavapipe software Vulkan driver (needed when DXVK fails on the GPU)
  --include-broken    keep the effects in SHADER_BROKEN_EFFECTS and verify they still fail
  --timeout SECONDS   longest wait for all effects to be reported (default 1800)
  --stall SECONDS     give up when no effect is reported for this long (default 180)
  --purge             delete the cache directory and exit
  --help              show this text

Downloads about 700 MB on the first run (GE-Proton, a mingw toolchain, ReShade) and needs
about 4 GB with every pack cloned. A window opens while it runs; leave it alone.
EOF
}

die() {
    local _status="$1"
    shift
    printf 'compile_check: %s\n' "$*" >&2
    exit "$_status"
}

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            --packs) needs_value "$@"; PACKS="$2"; shift 2 ;;
            --lab) needs_value "$@"; LAB="$2"; shift 2 ;;
            --software) SOFTWARE=1; shift ;;
            --include-broken) INCLUDE_BROKEN=1; shift ;;
            --timeout) needs_value "$@"; TIMEOUT_SECONDS="$2"; shift 2 ;;
            --stall) needs_value "$@"; STALL_SECONDS="$2"; shift 2 ;;
            --purge) PURGE=1; shift ;;
            --help|-h) usage; exit 0 ;;
            *) usage >&2; die 2 "unknown option: $1" ;;
        esac
    done
    [[ $TIMEOUT_SECONDS =~ ^[0-9]+$ && $STALL_SECONDS =~ ^[0-9]+$ ]] \
        || die 2 "--timeout and --stall take a number of seconds"
    # The run changes directory, so a relative path would stop pointing at the cache.
    LAB=$(realpath -m -- "$LAB")
}

needs_value() {
    (( $# >= 2 )) || die 2 "$1 needs a value"
}

# The cache is deleted with rm -rf, so only a directory this script created is accepted.
purge_lab() {
    [[ -f $LAB/.reshadelinux-compile-check ]] \
        || die 2 "$LAB was not created by compile_check.sh; refusing to delete it"
    rm -rf "$LAB"
    printf 'Removed %s\n' "$LAB"
}

check_prerequisites() {
    local _tool _missing=()

    for _tool in curl tar git python3 sha256sum find setsid uname; do
        command -v "$_tool" >/dev/null || _missing+=("$_tool")
    done
    (( ${#_missing[@]} == 0 )) || die 2 "missing required tools: ${_missing[*]}"
    # The pinned GE-Proton and llvm-mingw builds are x86_64 only.
    [[ $(uname -m) == x86_64 ]] || die 2 "this check needs an x86_64 machine (the pinned Proton and mingw builds are x86_64)"

    if [[ -z ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
        command -v xvfb-run >/dev/null || die 2 "no display found: run it from a desktop session or install xvfb-run"
        USE_XVFB=1
    fi
    if (( SOFTWARE )); then
        find_software_icd >/dev/null || die 2 "the lavapipe Vulkan driver is not installed (Arch: vulkan-swrast, Debian/Ubuntu: mesa-vulkan-drivers, Fedora: mesa-vulkan-drivers)"
    fi
}

find_software_icd() {
    local _icd
    for _icd in /usr/share/vulkan/icd.d/lvp_icd*.json /etc/vulkan/icd.d/lvp_icd*.json; do
        [[ -f $_icd ]] && { printf '%s\n' "$_icd"; return 0; }
    done
    return 1
}

# Download URL, check its SHA-256, and unpack it into DIR. Nothing is unpacked on a mismatch.
fetch_tool() {
    local _url="$1" _sha256="$2" _dir="$3" _archive _actual _rest

    [[ -f $_dir/.complete ]] && return 0
    mkdir -p "$LAB/downloads" "$_dir"
    _archive="$LAB/downloads/${_url##*/}"
    printf 'Downloading %s\n' "${_url##*/}"
    curl --fail --location --silent --show-error -o "$_archive" "$_url" \
        || die 2 "could not download $_url"
    read -r _actual _rest < <(sha256sum "$_archive")
    if [[ $_actual != "$_sha256" ]]; then
        rm -f "$_archive"
        rm -rf "$_dir"
        die 2 "checksum mismatch for ${_url##*/} (expected $_sha256, got $_actual)"
    fi
    tar -xf "$_archive" -C "$_dir" --strip-components=1 || die 2 "could not unpack ${_url##*/}"
    rm -f "$_archive"
    : > "$_dir/.complete"
}

ensure_tools() {
    fetch_tool "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$GE_PROTON_TAG/$GE_PROTON_TAG-x86_64.tar.gz" \
        "$GE_PROTON_SHA256" "$LAB/proton"
    if command -v x86_64-w64-mingw32-g++ >/dev/null; then
        MINGW_CXX="x86_64-w64-mingw32-g++"
    else
        fetch_tool "https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW_TAG/llvm-mingw-$LLVM_MINGW_TAG-ucrt-ubuntu-22.04-x86_64.tar.xz" \
            "$LLVM_MINGW_SHA256" "$LAB/mingw"
        MINGW_CXX="$LAB/mingw/bin/x86_64-w64-mingw32-g++"
    fi
    if [[ ! -x $LAB/d3dtest.exe || $SCRIPT_DIR/helpers/d3dtest.cpp -nt $LAB/d3dtest.exe ]]; then
        "$MINGW_CXX" -O1 -mwindows -static -o "$LAB/d3dtest.exe" "$SCRIPT_DIR/helpers/d3dtest.cpp" -ld3d11 -ldxgi \
            || die 2 "could not build the test program"
    fi
}

# ReShade64.dll comes out of the official installer, which is a zip with an .exe in front.
ensure_reshade() {
    local _html _link _url _version

    _html=$(curl --fail --silent --location --max-time 15 "$RESHADE_URL") || die 2 "could not reach $RESHADE_URL"
    _link=$(grep -oE '/downloads/ReShade_Setup_[0-9]+(\.[0-9]+)+\.exe' <<< "$_html" | head -n1) || true
    [[ -n $_link ]] || die 2 "could not read the ReShade version from $RESHADE_URL"
    _url="$RESHADE_URL$_link"
    validateReshadeDownloadUrl "$_url" || die 2 "unexpected ReShade download address"
    _version="${_link##*_Setup_}"
    _version="${_version%.exe}"
    RESHADE_CHECKED_VERSION="$_version"
    [[ -f $LAB/reshade/$_version/ReShade64.dll ]] && return 0

    mkdir -p "$LAB/reshade/$_version"
    curl --fail --location --silent --show-error -o "$LAB/reshade/$_version/setup.exe" "$_url" \
        || die 2 "could not download $_url"
    python3 - "$LAB/reshade/$_version/setup.exe" "$LAB/reshade/$_version" <<'PYEOF' || die 2 "could not unpack ReShade"
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extract("ReShade64.dll", sys.argv[2])
PYEOF
}

init_environment() {
    # --purge deletes the whole directory, and it trusts the marker written here. A directory that
    # already holds someone else's files must therefore never get the marker.
    if [[ -d $LAB && ! -f $LAB/.reshadelinux-compile-check && -n $(find "$LAB" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
        die 2 "$LAB is not empty and was not created by compile_check.sh; use an empty or new directory"
    fi
    mkdir -p "$LAB"
    : > "$LAB/.reshadelinux-compile-check"
    export MAIN_PATH="$LAB/data"
    export RESHADE_PATH="$MAIN_PATH/reshade"
    export UI_BACKEND=cli PROGRESS_UI=0 UPDATE_RESHADE=0 GIT_TERMINAL_PROMPT=0
    mkdir -p "$MAIN_PATH/ReShade_shaders" "$MAIN_PATH/External_shaders" "$MAIN_PATH/game-shaders" "$LAB/logs"
    init_runtime_config
}

# Print the comma-separated pack names to test, validating --packs against the registry.
resolve_packs() {
    local _entry _all="" _name
    local -A _known=()

    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        _known["$_shaderRepoName"]=1
        _all+="${_all:+,}$_shaderRepoName"
    done < <(listConfiguredShaderRepoEntries)

    if [[ $PACKS == all ]]; then
        printf '%s\n' "$_all"
        return 0
    fi
    for _name in ${PACKS//,/ }; do
        [[ -n ${_known["$_name"]+x} ]] || die 2 "unknown shader repository: $_name (see ./reshadelinux.sh --list-shader-repos)"
    done
    printf '%s\n' "$PACKS"
}

# Build the merged directory and a game folder holding ReShade as dxgi.dll, the pinned
# d3dcompiler_47.dll the installer links, and the test program.
prepare_game() {
    local _packs="$1"

    GAME_DIR="$LAB/game"
    KNOWN_BROKEN="$SHADER_BROKEN_EFFECTS"
    (( INCLUDE_BROKEN )) && SHADER_BROKEN_EFFECTS=""

    ensureSelectedShaderRepos "$_packs" || printf 'Some packs could not be cloned: %s\n' "${_failedRepos:-?}" >&2
    downloadD3dcompiler_47 64
    buildGameShaderDir "compile-check" "$_packs" > "$LAB/logs/build.log"

    rm -rf "$GAME_DIR"
    mkdir -p "$GAME_DIR"
    cp "$LAB/d3dtest.exe" "$GAME_DIR/"
    cp "$LAB/reshade/$RESHADE_CHECKED_VERSION/ReShade64.dll" "$GAME_DIR/dxgi.dll"
    cp "$MAIN_PATH/d3dcompiler_47.dll.64" "$GAME_DIR/d3dcompiler_47.dll"
    ln -sfn "$(realpath "$MAIN_PATH/game-shaders/compile-check")" "$GAME_DIR/ReShade_shaders"
    ensureGameIni "$GAME_DIR"
    EFFECT_COUNT=$(find -L "$GAME_DIR/ReShade_shaders/Merged/Shaders" -name '*.fx' | wc -l)
    # Nothing to wait for would end the run before ReShade has even started.
    (( EFFECT_COUNT > 0 )) || die 2 "no effect was merged; check the clone messages above and $LAB/logs/build.log"
}

# Number of effects ReShade has reported on so far, compiled or failed.
compile_progress() {
    if [[ -f $1 ]]; then
        grep -cE "(Successfully compiled|Failed to compile) '" "$1" || true
    else
        printf '0\n'
    fi
}

# kill -0 only probes; a finished process is the expected answer, not an error to print.
process_is_running() {
    kill -0 "$1" 2>/dev/null
}

# Poll until every effect is reported, nothing new is reported for STALL_SECONDS, or
# TIMEOUT_SECONDS pass. Returns 0 complete, 3 stalled or timed out, 4 the program ended early.
wait_for_compile() {
    local _log="$1" _expected="$2" _pid="$3" _reported=0 _now _idle=0 _waited=0

    while (( _waited < TIMEOUT_SECONDS )); do
        _now=$(compile_progress "$_log")
        (( _now >= _expected )) && return 0
        if (( _now > _reported )); then
            _reported=$_now
            _idle=0
        else
            _idle=$((_idle + POLL_SECONDS))
        fi
        (( _idle >= STALL_SECONDS )) && return 3
        process_is_running "$_pid" || return 4
        sleep "$POLL_SECONDS"
        _waited=$((_waited + POLL_SECONDS))
    done
    return 3
}

stop_proton() {
    [[ -n $PROTON_PID ]] || return 0
    if process_is_running "$PROTON_PID"; then
        kill -TERM -- "-$PROTON_PID" || true
    fi
    WINEPREFIX="$LAB/compat/pfx" "$LAB/proton/files/bin/wineserver" -k || true
    PROTON_PID=""
}

run_under_proton() {
    local _status=0 _wrapper=()

    mkdir -p "$LAB/compat" "$LAB/steam"
    (( USE_XVFB )) && _wrapper=(xvfb-run -a)
    if (( SOFTWARE )); then
        VK_ICD_FILENAMES=$(find_software_icd)
        export VK_ICD_FILENAMES
    fi
    rm -f "$GAME_DIR/ReShade.log"

    (
        cd "$GAME_DIR"
        export STEAM_COMPAT_DATA_PATH="$LAB/compat" STEAM_COMPAT_CLIENT_INSTALL_PATH="$LAB/steam"
        export WINEDLLOVERRIDES="dxgi=n,b;d3dcompiler_47=n,b" SteamAppId=0 SteamGameId=0
        export PROTON_LOG=1 PROTON_LOG_DIR="$LAB/logs" DXVK_LOG_LEVEL=warn
        exec setsid "${_wrapper[@]}" "$LAB/proton/proton" run ./d3dtest.exe "$((TIMEOUT_SECONDS + 120))"
    ) > "$LAB/logs/proton.out" 2>&1 &
    PROTON_PID=$!
    trap stop_proton EXIT
    trap 'exit 130' INT TERM

    printf 'Running ReShade on %s effects (this takes a while, leave the test window alone)...\n' "$EFFECT_COUNT"
    wait_for_compile "$GAME_DIR/ReShade.log" "$EFFECT_COUNT" "$PROTON_PID" || _status=$?
    stop_proton
    case $_status in
        3) printf 'compile_check: gave up waiting; reporting what was compiled.\n' >&2 ;;
        4) printf 'compile_check: the test program ended early; see %s/logs\n' "$LAB" >&2 ;;
    esac
}

report() {
    local _args=("$GAME_DIR/ReShade.log" "$GAME_DIR/ReShade_shaders/Merged/Shaders")

    (( INCLUDE_BROKEN )) && _args+=(--known-broken "$KNOWN_BROKEN")
    printf 'ReShade %s under %s\n' "$RESHADE_CHECKED_VERSION" "$GE_PROTON_TAG"
    python3 "$SCRIPT_DIR/helpers/compile_check_report.py" "${_args[@]}"
}

main() {
    local _packs _status=0

    parse_args "$@"
    if (( PURGE )); then
        purge_lab
        return 0
    fi
    check_prerequisites
    init_environment
    _packs=$(resolve_packs)
    ensure_tools
    ensure_reshade
    prepare_game "$_packs"
    run_under_proton
    report || _status=$?
    if (( _status == 2 && ! SOFTWARE )); then
        printf 'compile_check: if the GPU cannot run DXVK (see %s/logs/proton.out), retry with --software\n' "$LAB" >&2
    fi
    printf 'Logs: %s (delete the cache with --purge)\n' "$GAME_DIR/ReShade.log"
    return "$_status"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
