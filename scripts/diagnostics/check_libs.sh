#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./helpers/common.sh
source "$SCRIPT_DIR/helpers/common.sh"
# shellcheck source=./helpers/steam_report_common.sh
source "$SCRIPT_DIR/helpers/steam_report_common.sh"

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
        appid=$(extract_manifest_appid "$manifest")
        name=$(extract_manifest_name "$manifest")
        name="${name:0:50}"
        printf '  %s | %s | %s\n' "$appid" "$name" "$manifest"
        manifest_count["$appid"]=$((manifest_count["$appid"] + 1))
    done
done < <(listSteamAppsDirs)

echo ""
echo "=== Duplicate AppIDs Found Across Libraries ==="
print_duplicate_manifest_appids manifest_count