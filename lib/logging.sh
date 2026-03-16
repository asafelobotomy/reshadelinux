# shellcheck shell=bash

_R=$'\e[0m'
_B=$'\e[1m'
_RED=$'\e[31m'
_GRN=$'\e[32m'
_YLW=$'\e[33m'
_CYN=$'\e[36m'

function printStep() {
    printf '%b==> %s%b\n' "$_CYN$_B" "$1" "$_R"
}

function printErr() {
    printf '%b[ERROR] %s%b\n' "$_RED$_B" "$*" "$_R" >&2
    [[ ${_UI_BACKEND:-cli} == yad ]] && yad --error --title="ReShade - Error" --text="$*" --width=520 >/dev/null 2>&1 || true
    exit 1
}

function logDebug() {
    [[ -n ${RESHADE_DEBUG_LOG:-} ]] || return 0
    local _dir
    _dir=$(dirname "$RESHADE_DEBUG_LOG")
    mkdir -p "$_dir" 2>/dev/null || return 0
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$RESHADE_DEBUG_LOG" 2>/dev/null || true
}
