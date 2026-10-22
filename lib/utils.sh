# shellcheck shell=bash
# SPDX-License-Identifier: GPL-2.0-or-later

function checkStdin() {
    requireInput "a question needed an answer: $1"
    while true; do
        if ! read -rp "$(printf '%b%s%b' "$_YLW" "$1" "$_R")" userInput; then
            printf '\n' >&2
            printf '%b[ERROR] %s%b\n' "$_RED$_B" "Input closed while waiting for user response." "$_R" >&2
            return 1
        fi
        if [[ $userInput =~ $2 ]]; then
            break
        fi
    done
    echo "$userInput"
}

function setProgressText() {
    local _text="$1"
    _WITH_PROGRESS_TEXT="$_text"
    if [[ -n ${_WITH_PROGRESS_FILE:-} ]]; then
        printf '%s\n' "$_text" >"$_WITH_PROGRESS_FILE"
    fi
}

function withProgress() {
    local text="$1"; shift
    local _startTs _status
    _startTs=$(date +%s)
    logDebug "withProgress start backend=${_UI_BACKEND:-unknown} progress_ui=${PROGRESS_UI:-1} text=${text//$'\n'/ | }"
    if [[ ${PROGRESS_UI:-1} != 1 ]]; then
        "$@"
        _status=$?
        logDebug "withProgress finish backend=${_UI_BACKEND:-unknown} status=$_status elapsed=$(( $(date +%s) - _startTs ))s text=${text//$'\n'/ | }"
        return $_status
    fi
    if [[ $_UI_BACKEND == yad ]]; then
        _withYadProgress "$text" "$@"
        _status=$?
        logDebug "withProgress finish backend=yad status=$_status elapsed=$(( $(date +%s) - _startTs ))s text=${text//$'\n'/ | }"
        return $_status
    fi
    if [[ $_UI_BACKEND != cli ]]; then
        ui_infobox "ReShade" "$text" 10 70
        sleep 0.1
        ui_refresh_screen
    fi
    "$@"
    _status=$?
    logDebug "withProgress finish backend=${_UI_BACKEND:-unknown} status=$_status elapsed=$(( $(date +%s) - _startTs ))s text=${text//$'\n'/ | }"
    return $_status
}

# Copy text to the desktop clipboard with the first tool that works: wl-copy on Wayland, then xclip
# or xsel on X11 (Xwayland included, so an X tool still helps when wl-copy is missing or fails).
function copyToClipboard() {
    local _text="$1"
    if [[ -n ${WAYLAND_DISPLAY:-} ]] && command -v wl-copy &>/dev/null; then
        printf '%s' "$_text" | wl-copy >/dev/null 2>&1 && return 0
        logDebug "wl-copy could not copy to the clipboard"
    fi
    if [[ -n ${DISPLAY:-} ]] && command -v xclip &>/dev/null; then
        printf '%s' "$_text" | xclip -selection clipboard >/dev/null 2>&1 && return 0
        logDebug "xclip could not copy to the clipboard"
    fi
    if [[ -n ${DISPLAY:-} ]] && command -v xsel &>/dev/null; then
        printf '%s' "$_text" | xsel --clipboard --input >/dev/null 2>&1 && return 0
        logDebug "xsel could not copy to the clipboard"
    fi
    return 1
}

function createTempDir() {
    tmpDir=$(mktemp -d)
    cd "$tmpDir" || printErr "Failed to create temp directory."
}

function removeTempDir() {
    cd "$MAIN_PATH" || exit
    [[ -d ${tmpDir:-} ]] && rm -rf "$tmpDir"
}

# EXIT trap: remove a temp directory that a fatal error left behind. printErr exits
# the process, so callers cannot always clean up first. Safe to call repeatedly, and
# it only ever removes a directory that createTempDir made with mktemp.
function _cleanupTempDir() {
    [[ -n ${tmpDir:-} && -d $tmpDir && ${tmpDir##*/} == tmp.* ]] || return 0
    cd / || true
    rm -rf "$tmpDir"
    tmpDir=""
}
