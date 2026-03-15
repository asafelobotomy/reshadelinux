# shellcheck shell=bash

# Prompt user for a game path manually (TUI or CLI).
function promptGamePathManual() {
    if [[ $_UI_BACKEND != cli ]]; then
        local _startDir="$HOME/.local/share/Steam/steamapps/common"
        [[ ! -d $_startDir ]] && _startDir="$HOME"
        while true; do
            gamePath=$(ui_directorybox "ReShade - Select the game folder" "$_startDir") || exit 0
            if [[ -z $gamePath ]]; then
                ui_yesno "ReShade" "No folder entered. Exit the script?" 10 60 \
                    && exit 0
                continue
            fi
            gamePath="${gamePath/#\~/$HOME}"
            gamePath=$(realpath "$gamePath" 2>/dev/null)
            [[ -f $gamePath ]] && gamePath=$(dirname "$gamePath")
            if [[ -z $gamePath || ! -d $gamePath ]]; then
                ui_msgbox "ReShade" "Path does not exist:\n$gamePath" 12 70
                continue
            fi
            if ! compgen -G "$gamePath/*.exe" &>/dev/null; then
                ui_yesno "ReShade" "No .exe file found in:\n$gamePath\n\nUse this folder anyway?" 12 72 \
                    || { _startDir="$gamePath"; continue; }
            fi
            break
        done
        return
    fi

    printf '%bSupply the folder path where the main executable (.exe) for the game is.%b\n' "$_CYN" "$_R"
    printf '%b(Control+C to exit)%b\n' "$_YLW" "$_R"
    while true; do
        read -rp "$(printf '%bGame path: %b' "$_YLW" "$_R")" gamePath
        gamePath="${gamePath/#\~/$HOME}"
        gamePath=$(realpath "$gamePath" 2>/dev/null)
        [[ -f $gamePath ]] && gamePath=$(dirname "$gamePath")
        if [[ -z $gamePath || ! -d $gamePath ]]; then
            printf '%bIncorrect or empty path supplied. You supplied "%s".%b\n' "$_YLW" "$gamePath" "$_R"
            continue
        fi
        if ! compgen -G "$gamePath/*.exe" &>/dev/null; then
            printf '%bNo .exe file found in "%s".%b\n' "$_YLW" "$gamePath" "$_R"
            printf '%bDo you still want to use this directory?%b\n' "$_YLW" "$_R"
            local _useDirAnyway
            _useDirAnyway=$(checkStdin "(y/n) " "^(y|n)$") || exit 1
            [[ $_useDirAnyway != "y" ]] && continue
        fi
        printf '%bIs this path correct? "%s"%b\n' "$_YLW" "$gamePath" "$_R"
        local _pathConfirmed
        _pathConfirmed=$(checkStdin "(y/n) " "^(y|n)$") || exit 1
        [[ $_pathConfirmed == "y" ]] && return
    done
}

# Try to get game directory from user, preferring auto-detected Steam games.
function getGamePath() {
    detectSteamGames
    if [[ ${#DETECTED_GAME_PATHS[@]} -eq 0 ]]; then
        _selectedAppId=""
        promptGamePathManual
        return
    fi

    if [[ $_UI_BACKEND != cli ]]; then
        local _pick _i
        local -a _items=()
        if [[ $_UI_BACKEND == yad ]]; then
            # Multi-column layout: hidden key | Game | App ID | Executable
            for ((_i=0; _i<${#DETECTED_GAME_PATHS[@]}; _i++)); do
                _items+=("$((_i+1))" \
                    "$(_pango_escape "${DETECTED_GAME_NAMES[_i]}")" \
                    "${DETECTED_GAME_APPIDS[_i]}" \
                    "${DETECTED_GAME_EXES[_i]}")
            done
            _items+=("m" "Enter path manually..." "" "")
            local _pxHeight _pxWidth
            read -r _pxHeight _pxWidth < <(ui_yad_dims 26 130)
            _pick=$(ui_capture yad --list \
                --title="ReShade - Select Game" \
                --text="Detected installed Steam games. Double-click to select, or choose Manual path." \
                --column="Key" --column="Game" --column="App ID" --column="Executable" \
                --hide-column=1 --print-column=1 --separator="" \
                --height="$_pxHeight" --width="$_pxWidth" "${_items[@]}" 2>/dev/null) || exit 0
        else
            for ((_i=0; _i<${#DETECTED_GAME_PATHS[@]}; _i++)); do
                _items+=("$((_i+1))" "${DETECTED_GAME_NAMES[_i]} (${DETECTED_GAME_APPIDS[_i]}) — ${DETECTED_GAME_EXES[_i]}")
            done
            _items+=("m" "Manual path...")
            _pick=$(ui_menu "ReShade - Select Game" \
                "Detected installed Steam games. Choose one, or select manual path." \
                24 110 16 "${_items[@]}") || exit 0
        fi
        if [[ $_pick == "m" ]]; then
            _selectedAppId=""
            promptGamePathManual
        else
            _i=$((_pick - 1))
            gamePath="${DETECTED_GAME_PATHS[_i]}"
            _selectedAppId="${DETECTED_GAME_APPIDS[_i]}"
            printf '%bSelected auto-detected game path:%b %s\n' "$_GRN" "$_R" "$gamePath"
        fi
        return
    fi

    local _i _choice _maxShow=25 _statusLabel
    printf '%bDetected Steam games on this system:%b\n' "$_CYN$_B" "$_R"
    for ((_i=0; _i<${#DETECTED_GAME_PATHS[@]} && _i<_maxShow; _i++)); do
        _statusLabel="${DETECTED_GAME_NAMES[_i]}"
        printf '  %2d) %s (AppID %s)\n      exe: %s\n      -> %s\n' \
            "$((_i+1))" "$_statusLabel" "${DETECTED_GAME_APPIDS[_i]}" "${DETECTED_GAME_EXES[_i]}" "${DETECTED_GAME_PATHS[_i]}"
    done
    if [[ ${#DETECTED_GAME_PATHS[@]} -gt $_maxShow ]]; then
        printf '  ... showing first %d of %d detected games\n' "$_maxShow" "${#DETECTED_GAME_PATHS[@]}"
    fi
    printf '   m) Enter path manually\n'

    while true; do
        read -rp "$(printf '%bChoose game number or m: %b' "$_YLW" "$_R")" _choice
        if [[ $_choice =~ ^[mM]$ ]]; then
            _selectedAppId=""
            promptGamePathManual
            return
        fi
        if [[ $_choice =~ ^[0-9]+$ ]] && (( _choice >= 1 && _choice <= ${#DETECTED_GAME_PATHS[@]} )); then
            gamePath="${DETECTED_GAME_PATHS[$((_choice-1))]}"
            _selectedAppId="${DETECTED_GAME_APPIDS[$((_choice-1))]}"
            printf '%bSelected auto-detected game path:%b %s\n' "$_GRN" "$_R" "$gamePath"
            return
        fi
    done
}