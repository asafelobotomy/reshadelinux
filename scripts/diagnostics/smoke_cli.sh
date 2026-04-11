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

write_manifest() {
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

create_runtime_workspace() {
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

create_seeded_workspace() {
    local workspace_dir="$1"

    create_runtime_workspace "$workspace_dir"
    mkdir -p "$workspace_dir/game"
    touch "$workspace_dir/game/game.exe"
}

create_autodetect_workspace() {
    local workspace_dir="$1"
    local steamapps_dir="$workspace_dir/home/.local/share/Steam/steamapps"
    local game_root="$steamapps_dir/common/AutoDetectGame"

    create_runtime_workspace "$workspace_dir"
    mkdir -p "$game_root/bin/x64"
    touch "$game_root/bin/x64/AutoDetectGame.exe"
    write_manifest "$steamapps_dir" "424242" "Auto Detect Game" "AutoDetectGame"
}

create_retry_workspace() {
    local workspace_dir="$1"
    local fake_bin_dir="$workspace_dir/fake-bin"

    create_runtime_workspace "$workspace_dir"
    mkdir -p "$workspace_dir/game" "$fake_bin_dir" "$workspace_dir/fake-git-state"
    touch "$workspace_dir/game/game.exe"

    cat > "$fake_bin_dir/git" <<'EOF'
#!/usr/bin/env bash
set -eu

args=("$@")
target="${args[$(( ${#args[@]} - 1 ))]:-}"

case "${1:-}" in
    clone)
        printf 'git clone %s\n' "$target" >> "$FAKE_GIT_LOG"
        case "$target" in
            alpha)
                mkdir -p "$target/Shaders" "$target/Textures"
                printf '// alpha\n' > "$target/Shaders/alpha.fx"
                printf 'alpha\n' > "$target/Textures/alpha.png"
                ;;
            beta)
                if [[ ! -f "$FAKE_GIT_STATE_DIR/beta.failed_once" ]]; then
                    touch "$FAKE_GIT_STATE_DIR/beta.failed_once"
                    printf 'simulated beta clone failure\n' >> "$FAKE_GIT_LOG"
                    exit 1
                fi
                mkdir -p "$target/Shaders" "$target/Textures"
                printf '// beta\n' > "$target/Shaders/beta.fx"
                printf 'beta\n' > "$target/Textures/beta.png"
                ;;
            *)
                printf 'unexpected clone target: %s\n' "$target" >> "$FAKE_GIT_LOG"
                exit 1
                ;;
        esac
        ;;
    pull)
        printf 'git pull\n' >> "$FAKE_GIT_LOG"
        ;;
    *)
        printf 'unexpected git invocation: %s\n' "$*" >> "$FAKE_GIT_LOG"
        ;;
esac
EOF
    chmod +x "$fake_bin_dir/git"
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

run_autodetect_install_smoke() {
    local workspace_dir="$1"
    local install_log="$workspace_dir/autodetect-install.log"
    local game_dir="$workspace_dir/home/.local/share/Steam/steamapps/common/AutoDetectGame/bin/x64"
    local state_file="$workspace_dir/reshade/game-state/424242.state"
    local detected_dll

    printf '==> Running Steam autodetect CLI smoke test\n'
    printf 'i\n1\ny\n' | \
        HOME="$workspace_dir/home" \
        MAIN_PATH="$workspace_dir/reshade" \
        UI_BACKEND=cli \
        UPDATE_RESHADE=0 \
        SHADER_REPOS=';' \
        "$ENTRYPOINT" > "$install_log" 2>&1

    [[ -f "$state_file" ]]
    grep -q '^app_id=424242$' "$state_file"
    grep -q "^gamePath=${game_dir}$" "$state_file"
    detected_dll=$(grep '^dll=' "$state_file" | cut -d= -f2)
    [[ -n "$detected_dll" ]]
    assert_path_exists "$game_dir/$detected_dll.dll"
    grep -q 'Selected auto-detected game path:' "$install_log"

    printf 'Autodetect install log: %s\n' "$install_log"
}

run_shader_retry_smoke() {
    local workspace_dir="$1"
    local install_log="$workspace_dir/shader-retry.log"
    local git_log="$workspace_dir/fake-git.log"
    local game_dir="$workspace_dir/game"
    local state_file

    printf '==> Running offline shader retry smoke test\n'
    : > "$git_log"
    printf 'i\n%s\ny\ny\n\n\ny\n' "$game_dir" | \
        HOME="$workspace_dir/home" \
        MAIN_PATH="$workspace_dir/reshade" \
        UI_BACKEND=cli \
        UPDATE_RESHADE=0 \
        PATH="$workspace_dir/fake-bin:$PATH" \
        FAKE_GIT_LOG="$git_log" \
        FAKE_GIT_STATE_DIR="$workspace_dir/fake-git-state" \
        SHADER_REPOS='mock://alpha|alpha||Alpha smoke repo;mock://beta|beta||Beta smoke repo' \
        "$ENTRYPOINT" > "$install_log" 2>&1

    state_file=$(find "$workspace_dir/reshade/game-state" -maxdepth 1 -name '*.state' | head -n 1)
    [[ -n "$state_file" ]]
    grep -q '^selected_repos=alpha,beta$' "$state_file"
    assert_path_exists "$game_dir/ReShade_shaders/Merged/Shaders/alpha.fx"
    assert_path_exists "$game_dir/ReShade_shaders/Merged/Shaders/beta.fx"
    grep -q 'Retrying failed repositories' "$install_log"
    grep -q 'simulated beta clone failure' "$git_log"

    printf 'Shader retry log: %s\n' "$install_log"
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
    trap 'rm -rf "$SMOKE_ROOT"' EXIT

    printf 'Smoke workspace: %s\n' "$SMOKE_ROOT"
    create_seeded_workspace "$SMOKE_ROOT/manual"
    run_interactive_install_smoke "$SMOKE_ROOT/manual"
    run_batch_update_smoke "$SMOKE_ROOT/manual"
    create_autodetect_workspace "$SMOKE_ROOT/autodetect"
    run_autodetect_install_smoke "$SMOKE_ROOT/autodetect"
    create_retry_workspace "$SMOKE_ROOT/retry"
    run_shader_retry_smoke "$SMOKE_ROOT/retry"
    printf 'SMOKE_RESULT=PASS\n'
}

main "$@"