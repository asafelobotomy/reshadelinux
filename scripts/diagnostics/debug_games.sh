#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

detectSteamGames

echo "=== DETECTED GAMES ==="
for i in "${!DETECTED_GAME_APPIDS[@]}"; do
    echo "$((i + 1)). ${DETECTED_GAME_NAMES[i]} (AppID: ${DETECTED_GAME_APPIDS[i]}, Exe: ${DETECTED_GAME_EXES[i]})"
done

echo ""
echo "=== CHECKING FOR DUPLICATES ==="
declare -A appid_counts=()
for appid in "${DETECTED_GAME_APPIDS[@]}"; do
    ((appid_counts["$appid"]++))
done

for appid in "${!appid_counts[@]}"; do
    count=${appid_counts["$appid"]}
    if [[ $count -gt 1 ]]; then
        echo "AppID $appid appears $count times"
    fi
done

echo ""
echo "Total games detected: ${#DETECTED_GAME_APPIDS[@]}"