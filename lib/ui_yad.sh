# shellcheck shell=bash
# SPDX-License-Identifier: GPL-2.0-or-later

# yad specifics: text escaping, sizes, running a dialog with its stderr logged, message dialogs
# and the progress window.

# Escape text for a yad list cell (cells are read as pango markup). The replacements are
# quoted because bash 5.2 reads an unquoted & in a replacement as "the matched text", which
# turned "<" into "<lt;".
function _pango_escape() {
    local _s="$1"
    _s=${_s//&/'&amp;'}
    _s=${_s//</'&lt;'}
    _s=${_s//>/'&gt;'}
    printf '%s' "$_s"
}

# yad expands backslash escapes in dialog text: that is how the "\n" line breaks in our messages
# work, but it also turned a literal "\n" or "\t" in a game path into a line break or a tab.
# A value put into dialog text goes through this, which doubles its backslashes for yad (shown as
# one). whiptail and dialog read the text differently, so it is left alone for them.
function uiQuote() {
    if [[ ${_UI_BACKEND:-} == yad ]]; then
        printf '%s' "${1//\\/\\\\}"
    else
        printf '%s' "$1"
    fi
}

function ui_yad_dims() {
    local _height="${1:-14}" _width="${2:-70}"
    local _pxHeight=$((_height * 24)) _pxWidth=$((_width * 8))
    (( _pxHeight < 180 )) && _pxHeight=180
    (( _pxWidth < 420 )) && _pxWidth=420
    printf '%s %s\n' "$_pxHeight" "$_pxWidth"
}

# A scratch file for a dialog's stderr. When none can be made (a full or unwritable temporary
# directory, which is also when a fatal error most needs its dialog) the output is dropped:
# the dialog itself must still open.
function _ui_scratch_file() {
    mktemp || { logDebug "No temporary file for dialog output"; printf '/dev/null\n'; }
}

# Log what a dialog wrote to stderr, and remove its scratch file.
function _ui_scratch_done() {
    local _file="$1" _who="$2"

    if [[ $_file != /dev/null ]]; then
        [[ -s $_file ]] && logDebug "$_who wrote to stderr: $(<"$_file")"
        rm -f "$_file"
    fi
    return 0
}

# Run yad for a dialog whose answer is its exit status. yad's own complaints (a bad option
# exits 1, which a caller cannot tell from "cancel") go to the debug log, not into the void.
function _ui_yad_run() {
    local _errFile _status

    _errFile=$(_ui_scratch_file)
    ui_run yad "$@" >/dev/null 2>"$_errFile"
    _status=$?
    _ui_scratch_done "$_errFile" yad
    return $_status
}

# A message dialog with an icon and buttons. yad 15 has no --info/--question/--error
# dialog kinds (it exits with "Unknown option"), and a plain dialog works on every version.
function _ui_yad_message() {
    local _icon="$1" _title="$2" _text="$3" _height="$4" _width="$5" _pxHeight _pxWidth

    shift 5
    read -r _pxHeight _pxWidth < <(ui_yad_dims "$_height" "$_width")
    _ui_yad_run --no-markup --image="$_icon" --title="$_title" --text="$_text" \
        --height="$_pxHeight" --width="$_pxWidth" "$@"
}


# yad handles SIGTERM in its GTK main loop, so a window whose loop is stuck ignores it and a plain
# kill-then-wait hung the installer for good. Give it two seconds, then SIGKILL.
function _stopYadProgress() {
    local _pid="$1" _try

    kill "$_pid" 2>/dev/null || true
    for _try in {1..20}; do
        kill -0 "$_pid" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 "$_pid" 2>/dev/null; then
        logDebug "yad progress window $_pid ignored SIGTERM; killing it"
        kill -KILL "$_pid" 2>/dev/null || true
    fi
    wait "$_pid" 2>/dev/null || true
}

# Run "$@" under a pulsating yad progress window. The step text set with setProgressText goes to
# the bar and to an expanded log below it, where it is readable instead of small text inside the
# bar. Closing the window does not stop the operation; the writer then stops feeding it, since
# with nobody reading the pipe it would fill and block the run once the operation ends.
function _withYadProgress() {
    local _text="$1" _progressFile _stopFile _yadPipe _yadPipeFd _yadPid _writerPid _ret
    shift

    _progressFile=$(mktemp)
    _stopFile=$(mktemp)   # file existence signals the loop to keep running
    _yadPipe=$(mktemp -u)
    mkfifo "$_yadPipe"
    setProgressText "$_text"
    _WITH_PROGRESS_FILE="$_progressFile"
    exec {_yadPipeFd}<>"$_yadPipe"
    yad --progress --pulsate --no-buttons --auto-close \
        --enable-log="Details" --log-expanded --log-height=110 \
        --title="ReShade" --text="$_text" --width=560 <"$_yadPipe" >/dev/null 2>&1 &
    _yadPid=$!
    (
        set +x
        local _lastText="" _currentText
        while [[ -f "$_stopFile" ]] && kill -0 "$_yadPid" 2>/dev/null; do
            printf '1\n' >&$_yadPipeFd || break
            if [[ -f "$_progressFile" ]]; then
                _currentText=$(<"$_progressFile")
                if [[ "$_currentText" != "$_lastText" ]]; then
                    printf '#%s\n' "$_currentText" >&$_yadPipeFd || break
                    _lastText="$_currentText"
                fi
            fi
            sleep 0.1
        done
    ) &
    _writerPid=$!
    "$@"
    _ret=$?
    rm -f "$_stopFile"    # tell the loop to exit on next check
    wait "$_writerPid" 2>/dev/null || true
    exec {_yadPipeFd}>&-
    _stopYadProgress "$_yadPid"
    rm -f "$_progressFile" "$_yadPipe"
    unset _WITH_PROGRESS_FILE _WITH_PROGRESS_TEXT
    return $_ret
}
