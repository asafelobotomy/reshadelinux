#!/bin/bash

# shellcheck source=./common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

rm -f /tmp/game_detection.log
detectSteamGames

echo "=== Games Detected ==="
for i in "${!DETECTED_GAME_APPIDS[@]}"; do
    printf '%2d. [AppID %s] %s (%s)\n' "$((i + 1))" "${DETECTED_GAME_APPIDS[i]}" "${DETECTED_GAME_NAMES[i]}" "${DETECTED_GAME_EXES[i]}"
done

echo ""
echo "=== Detection Log ==="
[[ -f /tmp/game_detection.log ]] && cat /tmp/game_detection.log

echo ""
echo "=== Checking for Duplicates ==="
declare -A appid_list=()
for appid in "${DETECTED_GAME_APPIDS[@]}"; do
    if [[ -n ${appid_list["$appid"]+x} ]]; then
        echo "DUPLICATE: AppID $appid appears multiple times"
    fi
    appid_list["$appid"]=1
done