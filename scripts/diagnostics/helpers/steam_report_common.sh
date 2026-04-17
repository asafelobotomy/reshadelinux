#!/bin/bash

extract_manifest_appid() {
    local manifest="$1"
    grep -m1 -o '"appid"[[:space:]]*"[0-9]*"' "$manifest" | grep -o '[0-9]*'
}

extract_manifest_name() {
    local manifest="$1"
    grep -m1 -o '"name"[[:space:]]*"[^"]*"' "$manifest" | sed -E 's/.*"name"[[:space:]]*"([^"]*)".*/\1/'
}

print_detected_games_debug_list() {
    local index
    for index in "${!DETECTED_GAME_APPIDS[@]}"; do
        echo "$((index + 1)). ${DETECTED_GAME_NAMES[index]} (AppID: ${DETECTED_GAME_APPIDS[index]}, Exe: ${DETECTED_GAME_EXES[index]})"
    done
}

print_detected_games_report_list() {
    local index
    for index in "${!DETECTED_GAME_APPIDS[@]}"; do
        printf '%2d. [AppID %s] %s (%s)\n' \
            "$((index + 1))" \
            "${DETECTED_GAME_APPIDS[index]}" \
            "${DETECTED_GAME_NAMES[index]}" \
            "${DETECTED_GAME_EXES[index]}"
    done
}

print_detected_game_duplicate_counts() {
    local -A appid_counts=()
    local appid count

    for appid in "${DETECTED_GAME_APPIDS[@]}"; do
        ((appid_counts["$appid"]++))
    done

    for appid in "${!appid_counts[@]}"; do
        count=${appid_counts["$appid"]}
        if [[ $count -gt 1 ]]; then
            echo "AppID $appid appears $count times"
        fi
    done
}

print_duplicate_manifest_appids() {
    local -n manifest_count_ref="$1"
    local appid

    for appid in "${!manifest_count_ref[@]}"; do
        if (( manifest_count_ref["$appid"] > 1 )); then
            echo "AppID $appid found ${manifest_count_ref[$appid]} times"
        fi
    done
}