#!/usr/bin/env bash
# purpose:  Run an isolated dialog-backed smoke test without relying on the util-linux `script` command.
# when:     Use for local end-to-end verification of the dialog TUI path on systems where `dialog` exists but `script` does not.
# inputs:   Optional env vars TMPDIR, DIALOG_TRACE, SMOKE_KEEP_WORKSPACE, and TERM; no positional arguments.
# outputs:  Human-readable progress log to stdout and a final SMOKE_RESULT=PASS line on success.
# risk:     safe
# source:   original
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENTRYPOINT="$REPO_DIR/reshade-linux.sh"
SMOKE_ROOT=""
_DIALOG_FEEDER_PID=""

wait_for_dialog_widget() {
    local pattern="$1"
    local feeder_log="$2"
    local attempt

    for (( attempt = 0; attempt < 600; attempt++ )); do
        if ps -eo comm=,args= | awk -v pattern="$pattern" '
            {
                if ($1 == "dialog" && $0 ~ /dialog --clear --title ReShade/ && $0 ~ pattern) {
                    found = 1
                    exit
                }
            }
            END { exit(found ? 0 : 1) }
        '; then
            printf 'matched: %s\n' "$pattern" >> "$feeder_log"
            return 0
        fi
        sleep 0.1
    done

    printf 'timeout: %s\n' "$pattern" >> "$feeder_log"
    return 1
}

start_dialog_key_feeder() {
    local fifo_path="$1"
    local feeder_log="$2"

    (
        exec 3>"$fifo_path"

        wait_for_dialog_widget 'What would you like to do\?' "$feeder_log"
        printf '\r' >&3
        printf 'sent: radiolist enter\n' >> "$feeder_log"

        wait_for_dialog_widget 'Enter a directory path:' "$feeder_log"
        printf '\r' >&3
        printf 'sent: inputbox enter\n' >> "$feeder_log"
    ) >/dev/null 2>&1 &

    _DIALOG_FEEDER_PID="$!"
}

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
        "$workspace_dir/home/.local/share/Steam/steamapps/common" \
        "$workspace_dir/reshade/reshade/latest" \
        "$workspace_dir/reshade/game-state" \
        "$workspace_dir/reshade/game-shaders" \
        "$workspace_dir/reshade/ReShade_shaders/mock-dialog/Shaders" \
        "$workspace_dir/reshade/ReShade_shaders/mock-dialog/Textures"

    touch "$workspace_dir/home/.local/share/Steam/steamapps/common/game.exe"
    touch "$workspace_dir/reshade/reshade/latest/ReShade64.dll"
    touch "$workspace_dir/reshade/reshade/latest/ReShade32.dll"
    touch "$workspace_dir/reshade/d3dcompiler_47.dll.32"
    touch "$workspace_dir/reshade/d3dcompiler_47.dll.64"
    printf '// dialog smoke shader\n' > "$workspace_dir/reshade/ReShade_shaders/mock-dialog/Shaders/mock-dialog.fx"
    printf 'texture\n' > "$workspace_dir/reshade/ReShade_shaders/mock-dialog/Textures/mock-dialog.png"
}

run_dialog_install_smoke() {
    local workspace_dir="$1"
    local install_log="$workspace_dir/dialog-install.log"
    local feeder_log="$workspace_dir/dialog-feeder.log"
    local game_dir="$workspace_dir/home/.local/share/Steam/steamapps/common"
    local input_fifo="$workspace_dir/dialog-input.fifo"
    local installer_pid
    local state_file
    local term_value="${TERM:-xterm-256color}"

    printf '==> Running dialog install smoke test\n'
    mkfifo "$input_fifo"
    (
        exec 9<"$input_fifo"
        TERM="$term_value" \
        HOME="$workspace_dir/home" \
        MAIN_PATH="$workspace_dir/reshade" \
        UI_BACKEND=dialog \
        UI_AUTO_CONFIRM=1 \
        UPDATE_RESHADE=0 \
        SHADER_REPOS='local|mock-dialog||Dialog smoke repo' \
        DIALOGOPTS="--input-fd 9${DIALOG_TRACE:+ --trace $DIALOG_TRACE}" \
        "$ENTRYPOINT" > "$install_log" 2>&1
    ) &
    installer_pid="$!"

    : > "$feeder_log"
    start_dialog_key_feeder "$input_fifo" "$feeder_log"

    wait "$installer_pid"
    wait "$_DIALOG_FEEDER_PID" 2>/dev/null || true
    rm -f "$input_fifo"

    assert_path_exists "$game_dir/dxgi.dll"
    assert_path_exists "$game_dir/d3dcompiler_47.dll"
    assert_path_exists "$game_dir/ReShade_shaders"
    assert_path_exists "$game_dir/ReShade_shaders/Merged/Shaders/mock-dialog.fx"
    [[ -f "$game_dir/ReShade.ini" ]]

    state_file="$workspace_dir/reshade/game-state/path-$(printf '%s' "$game_dir" | sha256sum | cut -c1-16).state"
    [[ -f "$state_file" ]]
    grep -q '^selected_repos=mock-dialog$' "$state_file"

    printf 'Dialog install log: %s\n' "$install_log"
}

main() {
    if ! command -v dialog >/dev/null 2>&1; then
        printf 'dialog is not installed; cannot run dialog smoke test.\n' >&2
        exit 1
    fi

    SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/reshade-dialog-smoke.XXXXXX")"
    if [[ "${SMOKE_KEEP_WORKSPACE:-0}" != "1" ]]; then
        trap 'rm -rf "$SMOKE_ROOT"' EXIT
    fi

    printf 'Smoke workspace: %s\n' "$SMOKE_ROOT"
    create_seeded_workspace "$SMOKE_ROOT"
    run_dialog_install_smoke "$SMOKE_ROOT"
    printf 'SMOKE_RESULT=PASS\n'
}

main "$@"