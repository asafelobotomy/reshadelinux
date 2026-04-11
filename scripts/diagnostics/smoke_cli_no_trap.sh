#!/usr/bin/env bash
# purpose:  Run an isolated CLI smoke test that covers interactive install and seeded --update-all relink flows.
# when:     Use for local end-to-end verification of the CLI without touching real games or user ReShade data.
# inputs:   Optional env vars TMPDIR and UI_BACKEND; no positional arguments.
# outputs:  Human-readable progress log to stdout and a final SMOKE_RESULT=PASS line on success.
# risk:     safe
# source:   original
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENTRYPOINT="$REPO_DIR/reshade-linux.sh"
SMOKE_ROOT=""

assert_path_exists() {
    local path="$1"
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        printf 'Assertion failed: expected path to exist: %s\n' "$path" >&2
        return 1
    fi
}

create_seeded_workspace() {
    local workspace_dir="$1"
    mkdir -p \
        "$workspace_dir/home" \
        "$workspace_dir/game" \
        "$workspace_dir/reshade/reshade/latest" \
        "$workspace_dir/reshade/game-state" \
        "$workspace_dir/reshade/game-shaders"
    touch "$workspace_dir/game/game.exe"
    touch "$workspace_dir/reshade/reshade/latest/ReShade64.dll"
    touch "$workspace_dir/reshade/reshade/latest/ReShade32.dll"
    touch "$workspace_dir/reshade/d3dcompiler_47.dll.32"
    touch "$workspace_dir/reshade/d3dcompiler_47.dll.64"
}

run_interactive_install_smoke() {
    local workspace_dir="$1"
    local install_log="$workspace_dir/interactive-install.log"
    local game_dir="$workspace_dir/game"
    local state_file
    local detected_dll

    printf '==> Running interactive install smoke test\n'
    printf 'i\n%s\ny\ny\n' "$game_dir" | \
        HOME="$workspace_dir/home" \
        MAIN_PATH="$workspace_dir/reshade" \
        UI_BACKEND=cli \
        UPDATE_RESHADE=0 \
        SHADER_REPOS=';' \
        "$ENTRYPOINT" > "$install_log" 2>&1

    assert_path_exists "$game_dir/d3dcompiler_47.dll"
    assert_path_exists "$game_dir/ReShade_shaders"
    [[ -f "$game_dir/ReShade.ini" ]]

    state_file=$(find "$workspace_dir/reshade/game-state" -maxdepth 1 -name '*.state' | head -n 1)
    [[ -n "$state_file" ]]
    detected_dll=$(grep '^dll=' "$state_file" | cut -d= -f2)
    [[ -n "$detected_dll" ]]
    assert_path_exists "$game_dir/$detected_dll.dll"
    grep -Eq '^arch=(32|64)$' "$state_file"

    printf 'Interactive install log: %s\n' "$install_log"
}

run_batch_update_smoke() {
    local workspace_dir="$1"
    local update_log="$workspace_dir/update-all.log"
    local game_dir="$workspace_dir/game"

    printf '==> Running seeded --update-all smoke test\n'
    HOME="$workspace_dir/home" \
    MAIN_PATH="$workspace_dir/reshade" \
    UI_BACKEND=cli \
    UPDATE_RESHADE=0 \
    SHADER_REPOS=';' \
    "$ENTRYPOINT" --update-all > "$update_log" 2>&1

    local detected_dll
    detected_dll=$(grep '^dll=' "$workspace_dir/reshade/game-state/"*.state | head -n 1 | cut -d= -f2)
    [[ -n "$detected_dll" ]]
    assert_path_exists "$game_dir/$detected_dll.dll"
    assert_path_exists "$game_dir/d3dcompiler_47.dll"
    assert_path_exists "$game_dir/ReShade_shaders"
    [[ -f "$game_dir/ReShade.ini" ]]
    grep -q 'Batch update complete: 1 game(s) updated, 0 skipped.' "$update_log"

    printf 'Batch update log: %s\n' "$update_log"
}

main() {
    SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/reshade-cli-smoke.XXXXXX")"
    # trap removed

    printf 'Smoke workspace: %s\n' "$SMOKE_ROOT"
    create_seeded_workspace "$SMOKE_ROOT"
    run_interactive_install_smoke "$SMOKE_ROOT"
    run_batch_update_smoke "$SMOKE_ROOT"
    printf 'SMOKE_RESULT=PASS\n'
}

main "$@"