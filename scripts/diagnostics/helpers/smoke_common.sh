#!/usr/bin/env bash

SMOKE_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMOKE_COMMON_REPO_DIR="$(cd "$SMOKE_COMMON_DIR/../../.." && pwd)"
SMOKE_COMMON_ENTRYPOINT="$SMOKE_COMMON_REPO_DIR/reshade-linux.sh"

source "$SMOKE_COMMON_REPO_DIR/lib/state.sh"

assert_smoke_path_exists() {
    local path="$1"
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        printf 'Assertion failed: expected path to exist: %s\n' "$path" >&2
        return 1
    fi
}

create_smoke_runtime_workspace() {
    local workspace_dir="$1"

    mkdir -p \
        "$workspace_dir/home" \
        "$workspace_dir/reshade/reshade/latest" \
        "$workspace_dir/reshade/game-state" \
        "$workspace_dir/reshade/game-shaders"
    touch "$workspace_dir/reshade/reshade/latest/ReShade64.dll"
    touch "$workspace_dir/reshade/reshade/latest/ReShade32.dll"
    touch "$workspace_dir/reshade/d3dcompiler_47.dll.32"
    touch "$workspace_dir/reshade/d3dcompiler_47.dll.64"
}

write_smoke_manifest() {
    local steamapps_dir="$1"
    local app_id="$2"
    local game_name="$3"
    local install_dir="$4"

    cat > "$steamapps_dir/appmanifest_${app_id}.acf" <<EOF
"AppState"
{
    "appid"        "${app_id}"
    "name"         "${game_name}"
    "installdir"   "${install_dir}"
    "type"         "game"
}
EOF
}