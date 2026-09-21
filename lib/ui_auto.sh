# shellcheck shell=bash
# SPDX-License-Identifier: GPL-2.0-or-later

# The UI_AUTO_CONFIRM testing hook: answers dialogs without asking.

function ui_auto_respond_enabled() {
    [[ ${UI_AUTO_CONFIRM:-0} == 1 && $_UI_BACKEND != cli ]]
}

function ui_auto_select_first_tag() {
    local _tag _label _state

    while [[ $# -ge 3 ]]; do
        _tag="$1"
        _label="$2"
        _state="$3"
        if [[ $_state == ON ]]; then
            printf '%s\n' "$_tag"
            return 0
        fi
        shift 3
    done

    if [[ $# -ge 1 ]]; then
        printf '%s\n' "$1"
        return 0
    fi
    return 1
}

function ui_auto_select_checked_tags() {
    local _tag _label _state
    local -a _selected=()

    while [[ $# -ge 3 ]]; do
        _tag="$1"
        _label="$2"
        _state="$3"
        [[ $_state == ON ]] && _selected+=("$_tag")
        shift 3
    done

    local IFS=' '
    printf '%s\n' "${_selected[*]}"
}
