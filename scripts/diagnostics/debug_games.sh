#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./helpers/common.sh
source "$SCRIPT_DIR/helpers/common.sh"
# shellcheck source=./helpers/steam_report_common.sh
source "$SCRIPT_DIR/helpers/steam_report_common.sh"

detectSteamGames

echo "=== DETECTED GAMES ==="
print_detected_games_debug_list

echo ""
echo "=== CHECKING FOR DUPLICATES ==="
print_detected_game_duplicate_counts

echo ""
echo "Total games detected: ${#DETECTED_GAME_APPIDS[@]}"