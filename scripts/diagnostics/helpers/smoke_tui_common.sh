#!/usr/bin/env bash

SMOKE_TUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMOKE_TUI_ROOT=""

# shellcheck source=./smoke_common.sh
source "$SMOKE_TUI_DIR/smoke_common.sh"

create_tui_smoke_workspace() {
    local workspace_dir="$1"
    local repo_name="$2"
    local shader_comment="$3"

    create_smoke_runtime_workspace "$workspace_dir"
    mkdir -p \
        "$workspace_dir/home/.local/share/Steam/steamapps/common" \
        "$workspace_dir/reshade/ReShade_shaders/$repo_name/Shaders" \
        "$workspace_dir/reshade/ReShade_shaders/$repo_name/Textures"

    touch "$workspace_dir/home/.local/share/Steam/steamapps/common/game.exe"
    printf '// %s\n' "$shader_comment" > "$workspace_dir/reshade/ReShade_shaders/$repo_name/Shaders/$repo_name.fx"
    printf 'texture\n' > "$workspace_dir/reshade/ReShade_shaders/$repo_name/Textures/$repo_name.png"
}

run_tui_install_smoke() {
    local workspace_dir="$1"
    local backend="$2"
    local repo_name="$3"
    local repo_title="$4"
    local install_log="$workspace_dir/${backend}-install.log"
    local game_dir="$workspace_dir/home/.local/share/Steam/steamapps/common"
    local state_file

    printf '==> Running %s install smoke test\n' "$backend"
    TERM="${TERM:-xterm-256color}" \
    HOME="$workspace_dir/home" \
    MAIN_PATH="$workspace_dir/reshade" \
    UI_BACKEND="$backend" \
    UI_AUTO_CONFIRM=1 \
    UI_AUTO_INPUTBOX_RESPONSE="$game_dir" \
    UPDATE_RESHADE=0 \
    SHADER_REPOS="local|$repo_name||$repo_title" \
    "$SMOKE_COMMON_ENTRYPOINT" > "$install_log" 2>&1

    assert_smoke_path_exists "$game_dir/dxgi.dll"
    assert_smoke_path_exists "$game_dir/d3dcompiler_47.dll"
    assert_smoke_path_exists "$game_dir/ReShade_shaders"
    assert_smoke_path_exists "$game_dir/ReShade_shaders/Merged/Shaders/$repo_name.fx"
    [[ -f "$game_dir/ReShade.ini" ]]

    state_file="$workspace_dir/reshade/game-state/path-$(printf '%s' "$game_dir" | sha256sum | cut -c1-16).state"
    [[ -f "$state_file" ]]
    [[ $(readGameStateField "$state_file" selected_repos) == "$repo_name" ]]

    printf '%s install log: %s\n' "$backend" "$install_log"
}

run_tui_backend_smoke() {
    local backend="$1"
    local repo_name="$2"
    local repo_title="$3"
    local shader_comment="$4"

    if ! command -v "$backend" >/dev/null 2>&1; then
        printf '%s is not installed; cannot run %s smoke test.\n' "$backend" "$backend" >&2
        exit 1
    fi

    SMOKE_TUI_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/reshade-${backend}-smoke.XXXXXX")"
    if [[ "${SMOKE_KEEP_WORKSPACE:-0}" != "1" ]]; then
        trap 'rm -rf "$SMOKE_TUI_ROOT"' EXIT
    fi

    printf 'Smoke workspace: %s\n' "$SMOKE_TUI_ROOT"
    create_tui_smoke_workspace "$SMOKE_TUI_ROOT" "$repo_name" "$shader_comment"
    run_tui_install_smoke "$SMOKE_TUI_ROOT" "$backend" "$repo_name" "$repo_title"
    printf 'SMOKE_RESULT=PASS\n'
}