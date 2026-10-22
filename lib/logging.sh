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

# Exit statuses, so a script can tell "fix your command" from "try again later". They are
# documented in the README; never renumber one.
# shellcheck disable=SC2034  # used by the modules that source this file
{
    EXIT_FAILURE=1      # anything not listed below
    EXIT_USAGE=2        # a bad flag or value, or input that --no-input forbids asking for
    EXIT_DEPENDENCY=3   # a required program is missing
    EXIT_NETWORK=4      # a download or update check failed
    EXIT_INTEGRITY=5    # a download did not match its pinned checksum, or is not pinned
}

function printStep() {
    printf '%b==> %s%b\n' "$_CYN$_B" "$1" "$_R"
}

# Warnings go to stderr so that --quiet, which silences stdout, keeps them.
function printWarn() {
    printf '%b%s%b\n' "$_YLW" "$*" "$_R" >&2
}

function printErr() {
    local _code="${_errExitCode:-$EXIT_FAILURE}"
    printf '%b[ERROR] %s%b\n' "$_RED$_B" "$*" "$_R" >&2
    if [[ ${_UI_BACKEND:-cli} == yad ]]; then
        ui_error "ReShade - Error" "$*"
    fi
    exit "$_code"
}

# printErr with one of the EXIT_* statuses. The status travels in a variable, not an argument,
# so the tests' replacement printErr keeps working unchanged.
function failWith() {
    local _errExitCode="$1"
    shift
    printErr "$@"
}

# --quiet: stdout (progress, step headers, summaries) goes away and stderr (warnings, errors and
# prompts, which read -p writes there) stays. fd 3 keeps the real stdout for the few lines a script
# needs, such as the launch option, via printResult.
function enableQuietOutput() {
    exec 3>&1 1>/dev/null
    _RESULT_FD=3
}

function printResult() {
    printf '%s\n' "$*" >&"${_RESULT_FD:-1}"
}

function logDebug() {
    [[ -n ${RESHADE_DEBUG_LOG:-} ]] || return 0
    local _dir
    _dir=$(dirname "$RESHADE_DEBUG_LOG")
    mkdir -p "$_dir" 2>/dev/null || return 0
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$RESHADE_DEBUG_LOG" 2>/dev/null || true
}
