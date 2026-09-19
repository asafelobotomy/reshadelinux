# shellcheck shell=bash
# shellcheck disable=SC2153,SC2154

function checkRequiredExecutables() {
    local REQUIRED_EXECUTABLE _pkg
    local -a _required=("$@")

    if [[ ${#_required[@]} -eq 0 ]]; then
        _required=("${REQUIRED_EXECUTABLES[@]}")
    fi

    for REQUIRED_EXECUTABLE in "${_required[@]}"; do
        if ! command -v "$REQUIRED_EXECUTABLE" &>/dev/null; then
            printf "Program '%s' is missing, but it is required.\n" "$REQUIRED_EXECUTABLE"
            case "$REQUIRED_EXECUTABLE" in
                7z)   _pkg="p7zip-full" ;;
                curl) _pkg="curl" ;;
                file) _pkg="file" ;;
                git)  _pkg="git" ;;
                grep) _pkg="grep" ;;
                python3) _pkg="python3" ;;
                sed)  _pkg="sed" ;;
                sha256sum) _pkg="coreutils" ;;
                *) _pkg="$REQUIRED_EXECUTABLE" ;;
            esac
            if command -v apt-get &>/dev/null; then
                printf '  Install with:  sudo apt-get install %s\n' "$_pkg"
            elif command -v dnf &>/dev/null; then
                printf '  Install with:  sudo dnf install %s\n' "$_pkg"
            elif command -v pacman &>/dev/null; then
                printf '  Install with:  sudo pacman -S %s\n' "$_pkg"
            elif command -v zypper &>/dev/null; then
                printf '  Install with:  sudo zypper install %s\n' "$_pkg"
            fi
            printf 'Exiting.\n'
            exit 1
        fi
    done
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
