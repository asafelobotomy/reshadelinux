# shellcheck shell=bash
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck disable=SC2153,SC2154

# Print the package manager found on this system: apt, dnf, pacman or zypper.
function _detectPackageManager() {
    local _command

    for _command in apt-get dnf pacman zypper; do
        command -v "$_command" &>/dev/null || continue
        [[ $_command == apt-get ]] && _command=apt
        printf '%s\n' "$_command"
        return 0
    done
    return 1
}

# Print the package that provides a tool for a package manager. Fails when the name
# is not known, so the caller can suggest a package search instead of guessing.
function _packageNameFor() {
    local _tool="$1" _manager="$2"

    case "$_tool:$_manager" in
        7z:apt)         printf 'p7zip-full\n' ;;
        7z:pacman)      printf '7zip\n' ;;
        7z:*)           return 1 ;;
        python3:pacman) printf 'python\n' ;;
        sha256sum:*)    printf 'coreutils\n' ;;
        *)              printf '%s\n' "$_tool" ;;
    esac
}

function _installCommandFor() {
    case "$1" in
        apt)    printf 'sudo apt-get install' ;;
        dnf)    printf 'sudo dnf install' ;;
        pacman) printf 'sudo pacman -S' ;;
        zypper) printf 'sudo zypper install' ;;
    esac
}

# Print a command that lists the packages providing a tool.
function _packageSearchCommandFor() {
    local _manager="$1" _tool="$2"

    case "$_manager" in
        apt)    printf 'apt-file search bin/%s' "$_tool" ;;
        dnf)    printf "dnf provides '*/bin/%s'" "$_tool" ;;
        pacman) printf 'pacman -F %s' "$_tool" ;;
        zypper) printf 'zypper search --provides /usr/bin/%s' "$_tool" ;;
    esac
}

# Report every missing tool at once, with install hints, and stop. printErr also
# raises a dialog for the yad backend, so GUI users are not left with a silent exit.
function checkRequiredExecutables() {
    local _tool _manager _package _list _message
    local -a _required=("$@") _missing=() _packages=() _unknown=()

    if [[ ${#_required[@]} -eq 0 ]]; then
        _required=("${REQUIRED_EXECUTABLES[@]}")
    fi

    for _tool in "${_required[@]}"; do
        command -v "$_tool" &>/dev/null || _missing+=("$_tool")
    done
    [[ ${#_missing[@]} -eq 0 ]] && return 0

    _manager=$(_detectPackageManager) || _manager=""
    for _tool in "${_missing[@]}"; do
        if [[ -n $_manager ]] && _package=$(_packageNameFor "$_tool" "$_manager"); then
            _packages+=("$_package")
        else
            _unknown+=("$_tool")
        fi
    done

    printf -v _list '%s, ' "${_missing[@]}"
    _message="Missing required program(s): ${_list%, }"
    if [[ ${#_packages[@]} -gt 0 ]]; then
        _message+=$'\n'"Install with:  $(_installCommandFor "$_manager") ${_packages[*]}"
    fi
    if [[ -n $_manager ]]; then
        for _tool in "${_unknown[@]}"; do
            _message+=$'\n'"Find a package that provides '$_tool' with:  $(_packageSearchCommandFor "$_manager" "$_tool")"
        done
    fi

    printErr "$_message"
    return 1
}

function listRequiredExecutablesForMode() {
    local _mode="$1"

    case "$_mode" in
        selection)
            printf '%s\n' grep python3 sed sha256sum
            ;;
        install|batch-update)
            printf '%s\n' "${REQUIRED_EXECUTABLES[@]}"
            ;;
        *)
            printErr "Unknown executable-check mode '$_mode'."
            return 1
            ;;
    esac
}

function checkRequiredExecutablesForMode() {
    local _mode="$1"
    local -a _required=()
    local _tool

    while IFS= read -r _tool || [[ -n $_tool ]]; do
        _required+=("$_tool")
    done < <(listRequiredExecutablesForMode "$_mode")

    checkRequiredExecutables "${_required[@]}"
}
