# shellcheck shell=bash
# SPDX-License-Identifier: GPL-2.0-or-later

function ensureUiBackendAvailable() {
    local _backend="$1"

    case "$_backend" in
        cli)
            return 0
            ;;
        yad|whiptail|dialog)
            if ! command -v "$_backend" &>/dev/null; then
                printErr "Requested UI backend '$_backend' is not installed or not on PATH."
                return 1
            fi
            return 0
            ;;
        *)
            printErr "Invalid UI backend '$_backend'."
            return 1
            ;;
    esac
}

function chooseUiBackend() {
    local _hasTty="${1:-0}"
    local _forced="${UI_BACKEND:-auto}"
    case $_forced in
        auto) ;;
        yad|whiptail|dialog|cli)
            ensureUiBackendAvailable "$_forced" || return 1
            printf '%s\n' "$_forced"
            return
            ;;
        *)
            printErr "Invalid UI_BACKEND='$_forced'. Expected one of: auto, yad, whiptail, dialog, cli."
            return 1
            ;;
    esac
    if [[ $_hasTty -eq 1 ]]; then
        if command -v whiptail &>/dev/null; then
            printf 'whiptail\n'
            return
        fi
        if command -v dialog &>/dev/null; then
            printf 'dialog\n'
            return
        fi
    fi
    if [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && command -v yad &>/dev/null; then
        printf 'yad\n'
        return
    fi
    printf 'cli\n'
}

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

function ui_yad_dims() {
    local _height="${1:-14}" _width="${2:-70}"
    local _pxHeight=$((_height * 24)) _pxWidth=$((_width * 8))
    (( _pxHeight < 180 )) && _pxHeight=180
    (( _pxWidth < 420 )) && _pxWidth=420
    printf '%s %s\n' "$_pxHeight" "$_pxWidth"
}

function ui_capture() {
    local _result _status _errFile _had_errexit=0
    [[ $- == *e* ]] && _had_errexit=1
    set +e
    case $_UI_BACKEND in
        whiptail)
            _result=$("$@" 3>&1 1>&2 2>&3)
            _status=$?
            ;;
        dialog)
            _result=$("$@" 3>&1 1>/dev/tty 2>&3)
            _status=$?
            ;;
        *)
            _errFile=$(_ui_scratch_file)
            _result=$("$@" 2>"$_errFile")
            _status=$?
            _ui_scratch_done "$_errFile" "$1"
            ;;
    esac
    [[ $_had_errexit -eq 1 ]] && set -e
    ui_refresh_screen
    printf '%s' "$_result"
    return $_status
}

function ui_refresh_screen() {
    [[ $_UI_BACKEND == cli || $_UI_BACKEND == yad ]] && return 0
    local _ui_out="/dev/tty"
    [[ -w $_ui_out ]] || _ui_out="/dev/stderr"
    if command -v tput &>/dev/null; then
        tput sgr0 >"$_ui_out" 2>/dev/null || true
        tput cnorm >"$_ui_out" 2>/dev/null || true
        tput clear >"$_ui_out" 2>/dev/null || printf '\033[0m\033[H\033[2J\033[3J' >"$_ui_out"
        return 0
    fi
    printf '\033[0m\033[H\033[2J\033[3J' >"$_ui_out"
}

function ui_run() {
    local _status _had_errexit=0
    [[ $- == *e* ]] && _had_errexit=1
    set +e
    "$@"
    _status=$?
    [[ $_had_errexit -eq 1 ]] && set -e
    ui_refresh_screen
    return $_status
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

# A message dialog with the given icon (dialog-information, dialog-warning).
function _ui_msgbox() {
    local _icon="$1" _title="$2" _text="$3" _height="${4:-14}" _width="${5:-70}"
    [[ ${UI_AUTO_CONFIRM:-0} == 1 ]] && return 0
    case $_UI_BACKEND in
        yad) _ui_yad_message "$_icon" "$_title" "$_text" "$_height" "$_width" --button=OK:0 ;;
        whiptail) ui_run whiptail --clear --title "$_title" --msgbox "$_text" "$_height" "$_width" ;;
        dialog) ui_run dialog --clear --title "$_title" --msgbox "$_text" "$_height" "$_width" ;;
        *) return 0 ;;
    esac
}

function ui_msgbox() {
    _ui_msgbox dialog-information "$1" "$2" "${3:-14}" "${4:-70}"
}

# For something the user should correct or be told went wrong, without stopping the program.
function ui_warnbox() {
    _ui_msgbox dialog-warning "$1" "$2" "${3:-14}" "${4:-70}"
}

function ui_yesno() {
    local _title="$1" _text="$2" _height="${3:-12}" _width="${4:-70}"
    [[ ${UI_AUTO_CONFIRM:-0} == 1 ]] && return 0
    case $_UI_BACKEND in
        # yad focuses its first button, so Yes goes first: Enter answers Yes, as in whiptail and dialog.
        yad) _ui_yad_message dialog-question "$_title" "$_text" "$_height" "$_width" --button=Yes:0 --button=No:1 ;;
        whiptail) ui_run whiptail --clear --title "$_title" --yesno "$_text" "$_height" "$_width" ;;
        dialog) ui_run dialog --clear --title "$_title" --yesno "$_text" "$_height" "$_width" ;;
        *) return 1 ;;
    esac
}

# Error dialog for the graphical backend only: the other backends print to the terminal.
function ui_error() {
    local _title="$1" _text="$2" _height="${3:-10}" _width="${4:-65}"
    [[ ${_UI_BACKEND:-} == yad ]] || return 0
    _ui_yad_message dialog-error "$_title" "$_text" "$_height" "$_width" --button=Close:0
}

function ui_inputbox() {
    local _title="$1" _text="$2" _default="${3:-}" _height="${4:-14}" _width="${5:-78}"
    local _pxHeight _pxWidth

    if ui_auto_respond_enabled; then
        printf '%s\n' "${UI_AUTO_INPUTBOX_RESPONSE:-$_default}"
        return 0
    fi

    case $_UI_BACKEND in
        yad)
            read -r _pxHeight _pxWidth < <(ui_yad_dims "$_height" "$_width")
            ui_capture yad --entry --title="$_title" --text="$_text" --entry-text="$_default" --height="$_pxHeight" --width="$_pxWidth"
            ;;
        whiptail) ui_capture whiptail --clear --title "$_title" --inputbox "$_text" "$_height" "$_width" "$_default" ;;
        dialog) ui_capture dialog --clear --title "$_title" --inputbox "$_text" "$_height" "$_width" "$_default" ;;
        *) return 1 ;;
    esac
}

function ui_directorybox() {
    local _title="$1" _startDir="${2:-$HOME}" _height="${3:-24}" _width="${4:-95}"
    local _pxHeight _pxWidth
    case $_UI_BACKEND in
        yad)
            read -r _pxHeight _pxWidth < <(ui_yad_dims "$_height" "$_width")
            ui_capture yad --file --directory --title="$_title" --filename="$_startDir/" --height="$_pxHeight" --width="$_pxWidth"
            ;;
        *)
            ui_inputbox "$_title" "Enter a directory path:" "$_startDir/" "$_height" "$_width"
            ;;
    esac
}

function ui_menu() {
    local _title="$1" _text="$2" _height="$3" _width="$4" _menuHeight="$5"
    local _pxHeight _pxWidth
    shift 5

    if ui_auto_respond_enabled; then
        if [[ -n ${UI_AUTO_MENU_RESPONSE:-} ]]; then
            printf '%s\n' "$UI_AUTO_MENU_RESPONSE"
            return 0
        fi
        ui_auto_select_first_tag "$@"
        return $?
    fi

    case $_UI_BACKEND in
        yad)
            local -a _yadArgs=()
            local _toggle=0
            while [[ $# -ge 1 ]]; do
                if (( _toggle )); then
                    _yadArgs+=("$(_pango_escape "$1")")
                else
                    _yadArgs+=("$1")
                fi
                _toggle=$((1 - _toggle))
                shift
            done
            read -r _pxHeight _pxWidth < <(ui_yad_dims "$_height" "$_width")
            ui_capture yad --list --title="$_title" --text="$_text" \
                --column="Key" --column="Choice" --hide-column=1 --print-column=1 --separator="" \
                --height="$_pxHeight" --width="$_pxWidth" "${_yadArgs[@]}"
            ;;
        whiptail) ui_capture whiptail --clear --title "$_title" --menu "$_text" "$_height" "$_width" "$_menuHeight" "$@" ;;
        dialog) ui_capture dialog --clear --title "$_title" --menu "$_text" "$_height" "$_width" "$_menuHeight" "$@" ;;
        *) return 1 ;;
    esac
}

function ui_radiolist() {
    local _title="$1" _text="$2" _height="$3" _width="$4" _listHeight="$5"
    local _pxHeight _pxWidth _tag _label _state
    shift 5

    if ui_auto_respond_enabled; then
        if [[ -n ${UI_AUTO_RADIOLIST_RESPONSE:-} ]]; then
            printf '%s\n' "$UI_AUTO_RADIOLIST_RESPONSE"
            return 0
        fi
        ui_auto_select_first_tag "$@"
        return $?
    fi

    case $_UI_BACKEND in
        yad)
            # A radio button only moves when its own cell is clicked, so a user who clicked a
            # label and pressed OK got the pre-selected option. A plain list answers with the
            # highlighted row instead. yad highlights the first row, so the default goes first.
            local -a _first=() _others=()
            while [[ $# -ge 3 ]]; do
                _tag="$1"; _label="$(_pango_escape "$2")"; _state="$3"; shift 3
                if [[ $_state == ON && ${#_first[@]} -eq 0 ]]; then
                    _first=("$_tag" "$_label")
                else
                    _others+=("$_tag" "$_label")
                fi
            done
            read -r _pxHeight _pxWidth < <(ui_yad_dims "$_height" "$_width")
            ui_capture yad --list --title="$_title" --text="$_text" \
                --column="Key" --column="Choice" --hide-column=1 \
                --print-column=1 --separator="" --height="$_pxHeight" --width="$_pxWidth" \
                "${_first[@]}" "${_others[@]}"
            ;;
        whiptail) ui_capture whiptail --clear --title "$_title" --radiolist "$_text" "$_height" "$_width" "$_listHeight" "$@" ;;
        dialog) ui_capture dialog --clear --title "$_title" --radiolist "$_text" "$_height" "$_width" "$_listHeight" "$@" ;;
        *) return 1 ;;
    esac
}

function ui_checklist() {
    local _title="$1" _text="$2" _height="$3" _width="$4" _listHeight="$5"
    local _pxHeight _pxWidth _tag _label _state _yadState
    local -a _rows=()
    shift 5

    if ui_auto_respond_enabled; then
        if [[ -n ${UI_AUTO_CHECKLIST_RESPONSE:-} ]]; then
            printf '%s\n' "$UI_AUTO_CHECKLIST_RESPONSE"
            return 0
        fi
        ui_auto_select_checked_tags "$@"
        return 0
    fi

    case $_UI_BACKEND in
        yad)
            # "Select all" and "Select none" answer with their own exit status; the dialog is then
            # opened again with every row ticked or unticked. Alt+A and Alt+N are the shortcuts.
            local -a _args=("$@")
            local _setAll="" _out _status
            read -r _pxHeight _pxWidth < <(ui_yad_dims "$_height" "$_width")
            while true; do
                _rows=()
                set -- "${_args[@]}"
                while [[ $# -ge 3 ]]; do
                    _tag="$1"; _label="$(_pango_escape "$2")"; _state="$3"; shift 3
                    [[ $_setAll == all ]] && _state=ON
                    [[ $_setAll == none ]] && _state=OFF
                    [[ $_state == ON ]] && _yadState=TRUE || _yadState=FALSE
                    _rows+=("$_yadState" "$_tag" "$_label")
                done
                _out=$(ui_capture yad --list --checklist --title="$_title" --text="$_text" \
                    --column="" --column="Key" --column="Choice" --hide-column=2 \
                    --print-column=2 --separator=" " --height="$_pxHeight" --width="$_pxWidth" \
                    --button="Select _all:10" --button="Select _none:11" --button=Cancel:1 --button=OK:0 \
                    "${_rows[@]}")
                _status=$?
                case $_status in
                    10) _setAll=all ;;
                    11) _setAll=none ;;
                    *) printf '%s' "$_out"; return $_status ;;
                esac
            done
            ;;
        whiptail) ui_capture whiptail --clear --title "$_title" --checklist "$_text" "$_height" "$_width" "$_listHeight" "$@" ;;
        dialog) ui_capture dialog --clear --title "$_title" --checklist "$_text" "$_height" "$_width" "$_listHeight" "$@" ;;
        *) return 1 ;;
    esac
}

function ui_infobox() {
    local _title="$1" _text="$2" _height="${3:-10}" _width="${4:-70}"
    case $_UI_BACKEND in
        whiptail) whiptail --title "$_title" --infobox "$_text" "$_height" "$_width" ;;
        dialog) dialog --title "$_title" --infobox "$_text" "$_height" "$_width" ;;
        *) return 0 ;;
    esac
}
