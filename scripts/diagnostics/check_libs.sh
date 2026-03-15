#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

echo "=== Steam Libraries Found ==="
listSteamAppsDirs | nl

echo ""
echo "=== Manifest Files in All Libraries ==="
declare -A manifest_count=()
while read -r lib; do
    [[ -d "$lib" ]] || continue
    echo "Library: $lib"
    for manifest in "$lib"/appmanifest_*.acf; do
        [[ -f "$manifest" ]] || continue
        appid=$(grep -m1 -o '"appid"[[:space:]]*"[0-9]*"' "$manifest" | grep -o '[0-9]*')
        name=$(grep -m1 -o '"name"[[:space:]]*"[^"]*"' "$manifest" | sed -E 's/.*"name"[[:space:]]*"([^"]*)".*/\1/')
        name="${name:0:50}"
        printf '  %s | %s | %s\n' "$appid" "$name" "$manifest"
        manifest_count["$appid"]=$((manifest_count["$appid"] + 1))
    done
done < <(listSteamAppsDirs)

echo ""
echo "=== Duplicate AppIDs Found Across Libraries ==="
for appid in "${!manifest_count[@]}"; do
    if (( manifest_count["$appid"] > 1 )); then
        echo "AppID $appid found ${manifest_count[$appid]} times"
    fi
done