#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./helpers/common.sh
source "$SCRIPT_DIR/helpers/common.sh"

rm -f /tmp/game_detection.log

echo "=== Simulating getGamePath for INSTALL (main path) ==="
detectSteamGames

echo "Games after detectSteamGames:"
for i in "${!DETECTED_GAME_APPIDS[@]}"; do
    printf '  %d: AppID %s\n' "$i" "${DETECTED_GAME_APPIDS[i]}"
done

declare -a items=()
for ((i = 0; i < ${#DETECTED_GAME_PATHS[@]}; i++)); do
    status_label="${DETECTED_GAME_NAMES[i]}"
    items+=("$((i + 1))" "$status_label | AppID ${DETECTED_GAME_APPIDS[i]} | ${DETECTED_GAME_EXES[i]}")
done

echo ""
echo "=== Menu Items (what YAD would show) ==="
for ((i = 0; i < ${#items[@]}; i += 2)); do
    printf '%s. %s\n' "${items[i]}" "${items[((i + 1))]}"
done

echo ""
echo "=== Checking for Duplicates in Menu ==="
for ((i = 1; i < ${#items[@]}; i += 2)); do
    for ((j = i + 2; j < ${#items[@]}; j += 2)); do
        if [[ "${items[i]}" == "${items[j]}" ]]; then
            echo "DUPLICATE: ${items[i]}"
        fi
    done
done

echo ""
echo "=== Detection Log ==="
[[ -f /tmp/game_detection.log ]] && cat /tmp/game_detection.log