#!/usr/bin/env bash

SMOKE_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMOKE_COMMON_REPO_DIR="$(cd "$SMOKE_COMMON_DIR/../../.." && pwd)"
# shellcheck disable=SC2034  # used by the smoke helpers that source this file
SMOKE_COMMON_ENTRYPOINT="$SMOKE_COMMON_REPO_DIR/reshadelinux.sh"

source "$SMOKE_COMMON_REPO_DIR/lib/state.sh"

# EXIT trap for the smoke runners. A failing run keeps its workspace and prints the tail
# of every log in it, so the reason is never deleted along with the temp directory.
# SMOKE_KEEP_WORKSPACE=1 also keeps the workspace after a passing run.
smoke_finish() {
    local status=$? root="$1" log

    if [[ $status -ne 0 ]]; then
        printf 'SMOKE_RESULT=FAIL (workspace kept: %s)\n' "$root" >&2
        while IFS= read -r log; do
            # Some libraries leave binary files with a .log name in the workspace's HOME.
            grep -Iq . "$log" || continue
            printf '\n--- %s ---\n' "$log" >&2
            tail -n 20 "$log" >&2
        done < <(find "$root" -name '*.log' -type f 2>/dev/null | sort)
    elif [[ ${SMOKE_KEEP_WORKSPACE:-0} != 1 ]]; then
        rm -rf "$root"
    fi
}

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
