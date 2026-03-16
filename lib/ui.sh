# shellcheck shell=bash

function chooseUiBackend() {
    local _hasTty="${1:-0}"
    local _forced="${UI_BACKEND:-auto}"
    case $_forced in
        auto) ;;
        yad|whiptail|dialog|cli)
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

function _pango_escape() {
    local _s="$1"
    _s=${_s//&/&amp;}
    _s=${_s//</&lt;}
    _s=${_s//>/&gt;}
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
    local _result _status
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
            _result=$("$@")
            _status=$?
            ;;
    esac
    set -e
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
    local _status
    set +e
    "$@"
    _status=$?
    set -e
    ui_refresh_screen
    return $_status
}

function ui_msgbox() {
    local _title="$1" _text="$2" _height="${3:-14}" _width="${4:-70}"
    local _pxHeight _pxWidth
    [[ ${UI_AUTO_CONFIRM:-0} == 1 ]] && return 0
    case $_UI_BACKEND in
        yad)
            read -r _pxHeight _pxWidth < <(ui_yad_dims "$_height" "$_width")
            ui_run yad --info --title="$_title" --text="$_text" --height="$_pxHeight" --width="$_pxWidth" >/dev/null 2>&1
            ;;
        whiptail) ui_run whiptail --clear --title "$_title" --msgbox "$_text" "$_height" "$_width" ;;
        dialog) ui_run dialog --clear --title "$_title" --msgbox "$_text" "$_height" "$_width" ;;
        *) return 0 ;;
    esac
}

function ui_yesno() {
    local _title="$1" _text="$2" _height="${3:-12}" _width="${4:-70}"
    local _pxHeight _pxWidth
    [[ ${UI_AUTO_CONFIRM:-0} == 1 ]] && return 0
    case $_UI_BACKEND in
        yad)
            read -r _pxHeight _pxWidth < <(ui_yad_dims "$_height" "$_width")
            ui_run yad --question --title="$_title" --text="$_text" --height="$_pxHeight" --width="$_pxWidth" >/dev/null 2>&1
            ;;
        whiptail) ui_run whiptail --clear --title "$_title" --yesno "$_text" "$_height" "$_width" ;;
        dialog) ui_run dialog --clear --title "$_title" --yesno "$_text" "$_height" "$_width" ;;
        *) return 1 ;;
    esac
}

function ui_inputbox() {
    local _title="$1" _text="$2" _default="${3:-}" _height="${4:-14}" _width="${5:-78}"
    local _pxHeight _pxWidth
    case $_UI_BACKEND in
        yad)
            read -r _pxHeight _pxWidth < <(ui_yad_dims "$_height" "$_width")
            ui_capture yad --entry --title="$_title" --text="$_text" --entry-text="$_default" --height="$_pxHeight" --width="$_pxWidth" 2>/dev/null
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
            ui_capture yad --file --directory --title="$_title" --filename="$_startDir/" --height="$_pxHeight" --width="$_pxWidth" 2>/dev/null
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
                (( _toggle = !_toggle ))
                shift
            done
            read -r _pxHeight _pxWidth < <(ui_yad_dims "$_height" "$_width")
            ui_capture yad --list --title="$_title" --text="$_text" \
                --column="Key" --column="Choice" --print-column=1 --separator="" \
                --height="$_pxHeight" --width="$_pxWidth" "${_yadArgs[@]}" 2>/dev/null
            ;;
        whiptail) ui_capture whiptail --clear --title "$_title" --menu "$_text" "$_height" "$_width" "$_menuHeight" "$@" ;;
        dialog) ui_capture dialog --clear --title "$_title" --menu "$_text" "$_height" "$_width" "$_menuHeight" "$@" ;;
        *) return 1 ;;
    esac
}

function ui_radiolist() {
    local _title="$1" _text="$2" _height="$3" _width="$4" _listHeight="$5"
    local _pxHeight _pxWidth _tag _label _state _yadState
    local -a _rows=()
    shift 5
    case $_UI_BACKEND in
        yad)
            while [[ $# -ge 3 ]]; do
                _tag="$1"; _label="$(_pango_escape "$2")"; _state="$3"; shift 3
                [[ $_state == ON ]] && _yadState=TRUE || _yadState=FALSE
                _rows+=("$_yadState" "$_tag" "$_label")
            done
            read -r _pxHeight _pxWidth < <(ui_yad_dims "$_height" "$_width")
            ui_capture yad --list --radiolist --title="$_title" --text="$_text" \
                --column="" --column="Key" --column="Choice" --hide-column=2 \
                --print-column=2 --separator="" --height="$_pxHeight" --width="$_pxWidth" \
                "${_rows[@]}" 2>/dev/null
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
    case $_UI_BACKEND in
        yad)
            while [[ $# -ge 3 ]]; do
                _tag="$1"; _label="$(_pango_escape "$2")"; _state="$3"; shift 3
                [[ $_state == ON ]] && _yadState=TRUE || _yadState=FALSE
                _rows+=("$_yadState" "$_tag" "$_label")
            done
            read -r _pxHeight _pxWidth < <(ui_yad_dims "$_height" "$_width")
            ui_capture yad --list --checklist --title="$_title" --text="$_text" \
                --column="" --column="Key" --column="Choice" --hide-column=2 \
                --print-column=2 --separator=" " --height="$_pxHeight" --width="$_pxWidth" \
                "${_rows[@]}" 2>/dev/null
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
