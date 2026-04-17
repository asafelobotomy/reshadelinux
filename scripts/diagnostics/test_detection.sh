#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./helpers/common.sh
source "$SCRIPT_DIR/helpers/common.sh"
# shellcheck source=./helpers/steam_report_common.sh
source "$SCRIPT_DIR/helpers/steam_report_common.sh"

rm -f /tmp/game_detection.log
detectSteamGames

echo "=== Games Detected ==="
print_detected_games_report_list

echo ""
echo "=== Detection Log ==="
[[ -f /tmp/game_detection.log ]] && cat /tmp/game_detection.log

echo ""
echo "=== Checking for Duplicates ==="
print_detected_game_duplicate_counts