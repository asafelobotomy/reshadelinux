# shellcheck shell=bash
# SPDX-License-Identifier: GPL-2.0-or-later

# Colour only on a terminal, so logs and pipes stay readable, and never when NO_COLOR is set
# (https://no-color.org). CLICOLOR_FORCE=1 forces it, for example into a pager.
if [[ -z ${NO_COLOR:-} && ( -t 1 || -n ${CLICOLOR_FORCE:-} ) ]]; then
    _R=$'\e[0m'
    _B=$'\e[1m'
    _RED=$'\e[31m'
    _GRN=$'\e[32m'
    _YLW=$'\e[33m'
    _CYN=$'\e[36m'
else
    _R="" _B="" _RED="" _GRN="" _YLW="" _CYN=""
fi

function printStep() {
    printf '%b==> %s%b\n' "$_CYN$_B" "$1" "$_R"
}

function printErr() {
    printf '%b[ERROR] %s%b\n' "$_RED$_B" "$*" "$_R" >&2
    if [[ ${_UI_BACKEND:-cli} == yad ]]; then
        ui_error "ReShade - Error" "$*"
    fi
    exit 1
}

function logDebug() {
    [[ -n ${RESHADE_DEBUG_LOG:-} ]] || return 0
    local _dir
    _dir=$(dirname "$RESHADE_DEBUG_LOG")
    mkdir -p "$_dir" 2>/dev/null || return 0
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$RESHADE_DEBUG_LOG" 2>/dev/null || true
}
