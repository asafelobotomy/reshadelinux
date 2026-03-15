# shellcheck shell=bash

function checkStdin() {
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
    if [[ $_UI_BACKEND == yad ]]; then
        local _progressFile _stopFile _yadPid _ret
        _progressFile=$(mktemp)
        _stopFile=$(mktemp)   # file existence signals the loop to keep running
        setProgressText "$text"
        _WITH_PROGRESS_FILE="$_progressFile"
        (
            set +x
            local _lastText=""
            while [[ -f "$_stopFile" ]]; do
                printf '1\n' 2>/dev/null || true
                if [[ -f "$_progressFile" ]]; then
                    local _currentText
                    _currentText=$(<"$_progressFile")
                    if [[ "$_currentText" != "$_lastText" ]]; then
                        printf '#%s\n' "$_currentText" 2>/dev/null || true
                        _lastText="$_currentText"
                    fi
                fi
                sleep 0.1
            done
        ) \
            | yad --progress --pulsate --no-buttons --auto-close \
                  --title="ReShade" --text="$text" --width=520 >/dev/null 2>&1 &
        _yadPid=$!
        "$@"
        _ret=$?
        rm -f "$_stopFile"    # tell the loop to exit on next check
        sleep 0.15            # allow one loop cycle to complete and the subshell to exit
        kill "$_yadPid" 2>/dev/null || true
        wait "$_yadPid" 2>/dev/null || true
        rm -f "$_progressFile"
        unset _WITH_PROGRESS_FILE _WITH_PROGRESS_TEXT
        return $_ret
    fi
    if [[ $_UI_BACKEND != cli ]]; then
        ui_infobox "ReShade" "$text" 10 70
        sleep 0.1
        ui_refresh_screen
    fi
    "$@"
}

function copyToClipboard() {
    local _text="$1"
    if [[ -n ${WAYLAND_DISPLAY:-} ]] && command -v wl-copy &>/dev/null; then
        printf '%s' "$_text" | wl-copy >/dev/null 2>&1
        return $?
    fi
    if [[ -n ${DISPLAY:-} ]] && command -v xclip &>/dev/null; then
        printf '%s' "$_text" | xclip -selection clipboard >/dev/null 2>&1
        return $?
    fi
    if [[ -n ${DISPLAY:-} ]] && command -v xsel &>/dev/null; then
        printf '%s' "$_text" | xsel --clipboard --input >/dev/null 2>&1
        return $?
    fi
    return 1
}

function createTempDir() {
    tmpDir=$(mktemp -d)
    cd "$tmpDir" || printErr "Failed to create temp directory."
}

function removeTempDir() {
    cd "$MAIN_PATH" || exit
    [[ -d $tmpDir ]] && rm -rf "$tmpDir"
}
