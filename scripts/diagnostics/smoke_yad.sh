#!/usr/bin/env bash
# purpose:  Drive the real yad dialogs of the installer end to end on a private X server and check what each flow does to the files.
# when:     After changing lib/ui.sh, a dialog or any flow. Needs yad, Xvfb and xdotool (openbox and ImageMagick are optional); about two minutes. Never touches the desktop or a real Steam library.
# inputs:   Optional scenario names as arguments; env SMOKE_YAD_SHOTS=DIR to save a screenshot of every dialog, SMOKE_KEEP_WORKSPACE=1, SMOKE_YAD_DIALOG_WAIT=SECONDS (default 30).
# outputs:  One PASS or FAIL line per scenario and SMOKE_RESULT=PASS|FAIL. A failing run keeps its workspace.
# risk:     safe
# source:   original
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./helpers/smoke_yad_common.sh
source "$SCRIPT_DIR/helpers/smoke_yad_common.sh"

SMOKE_ROOT=""
GAME_BIN=""
STATE_DIR=""

# The dialogs of a default install, in order.
install_defaults() {
    yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade - Select Game" Return &&
        yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade - Shader Repositories" Return &&
        yadsmoke_answer "ReShade - Shaders" Return &&
        yadsmoke_answer "ReShade - Installation Complete" Return
}

# begin NAME [VAR=value...] [-- ARGUMENT...]: fresh workspace and a running installer.
begin() {
    YADSMOKE_SCENARIO="$1"
    shift
    WS="$SMOKE_ROOT/$YADSMOKE_SCENARIO"
    yadsmoke_workspace "$WS"
    GAME_BIN="$WS/home/.local/share/Steam/steamapps/common/AutoGame/bin"
    STATE_DIR="$WS/reshade/game-state"
    LOG="$WS/$YADSMOKE_SCENARIO.log"
    yadsmoke_start_app "$WS" "$LOG" "$@"
}

# finish EXPECTED_STATUS: wait for the installer and compare its exit status.
finish() {
    local _status

    _status=$(yadsmoke_app_status)
    [[ $_status == "$1" ]] || { printf 'exit status %s, expected %s\n' "$_status" "$1" >&2; return 1; }
}

state_field() { grep -h "^$1=" "$STATE_DIR"/*.state 2>/dev/null | head -n 1 | cut -d= -f2-; }

scenario_install_with_defaults() {
    begin install_with_defaults
    install_defaults && finish 0 || return 1
    [[ -L $GAME_BIN/dxgi.dll && -L $GAME_BIN/d3dcompiler_47.dll ]] || { echo "DLLs not linked" >&2; return 1; }
    grep -Fq 'Shaders\**' "$GAME_BIN/ReShade.ini" || { echo "ReShade.ini lacks the recursive search path" >&2; return 1; }
    [[ $(state_field selected_repos) == "repo-a,repo-b" ]] || { echo "unexpected selection" >&2; return 1; }
    [[ -L $GAME_BIN/ReShade_shaders/Merged/Shaders/repo-a.fx ]] || { echo "shaders not merged" >&2; return 1; }
}

scenario_cancel_at_the_first_dialog() {
    begin cancel_at_the_first_dialog
    yadsmoke_answer "ReShade" Escape && finish 0 || return 1
    [[ -z $(ls "$STATE_DIR" 2>/dev/null) ]] || { echo "state was written" >&2; return 1; }
}

scenario_cancel_at_the_game_picker() {
    begin cancel_at_the_game_picker
    yadsmoke_answer "ReShade" Return && yadsmoke_answer "ReShade - Select Game" Escape && finish 0 || return 1
    [[ ! -e $GAME_BIN/dxgi.dll ]] || { echo "a DLL was linked" >&2; return 1; }
}

scenario_game_with_markup_characters_in_its_name() {
    begin game_with_markup_characters_in_its_name
    yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade - Select Game" Down Return &&
        yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade - Shader Repositories" Return &&
        yadsmoke_answer "ReShade - Shaders" Return &&
        yadsmoke_answer "ReShade - Installation Complete" Return && finish 0 || return 1
    [[ $(state_field app_id) == 1002 ]] || { echo "the second game was not installed" >&2; return 1; }
}

scenario_unsupported_dll_name_is_rejected() {
    begin unsupported_dll_name_is_rejected
    yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade - Select Game" Return &&
        yadsmoke_answer "ReShade" Right Return &&
        yadsmoke_answer "ReShade" ctrl+a type:winmm Return &&
        yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade" ctrl+a type:d3d11 Return &&
        yadsmoke_answer "ReShade - Shader Repositories" Return &&
        yadsmoke_answer "ReShade - Shaders" Return &&
        yadsmoke_answer "ReShade - Installation Complete" Return && finish 0 || return 1
    [[ -L $GAME_BIN/d3d11.dll && ! -e $GAME_BIN/winmm.dll ]] || { echo "wrong DLL name linked" >&2; return 1; }
}

scenario_no_shader_packs_selected() {
    begin no_shader_packs_selected
    yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade - Select Game" Return &&
        yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade - Shader Repositories" space Down space Return &&
        yadsmoke_answer "ReShade - Installation Complete" Return && finish 0 || return 1
    [[ -z $(state_field selected_repos) ]] || { echo "a pack was still selected" >&2; return 1; }
}

# The shader picker has "Select all" and "Select none" buttons (Alt+A, Alt+N). Each reopens the
# dialog with every pack ticked or unticked.
scenario_shader_picker_select_all_and_none() {
    begin shader_picker_select_all_and_none
    yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade - Select Game" Return &&
        yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade - Shader Repositories" alt+n &&
        yadsmoke_answer "ReShade - Shader Repositories" alt+a &&
        yadsmoke_answer "ReShade - Shader Repositories" Return &&
        yadsmoke_answer "ReShade - Shaders" Return &&
        yadsmoke_answer "ReShade - Installation Complete" Return && finish 0 || return 1
    [[ $(state_field selected_repos) == "repo-a,repo-b" ]] || { echo "select all did not select every pack" >&2; return 1; }
}

scenario_shader_picker_select_none_installs_no_packs() {
    begin shader_picker_select_none_installs_no_packs
    yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade - Select Game" Return &&
        yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade - Shader Repositories" alt+n &&
        yadsmoke_answer "ReShade - Shader Repositories" Return &&
        yadsmoke_answer "ReShade - Installation Complete" Return && finish 0 || return 1
    [[ -z $(state_field selected_repos) ]] || { echo "a pack was still selected" >&2; return 1; }
}

scenario_failed_shader_download_offers_a_retry() {
    begin failed_shader_download_offers_a_retry SHADER_REPOS='file:///nonexistent/repo.git|broken-pack||Broken Pack|cannot be cloned'
    yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade - Select Game" Return &&
        yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade - Shader Repositories" Return &&
        yadsmoke_answer "ReShade - Download Error" Return &&
        yadsmoke_answer "ReShade - Download Error" Return &&
        yadsmoke_answer "ReShade - Installation Complete" Return && finish 0 || return 1
    [[ -L $GAME_BIN/dxgi.dll ]] || { echo "the install did not continue without the pack" >&2; return 1; }
}

# The action list answers with the highlighted row; a radio button used to keep the default.
scenario_action_list_follows_the_highlighted_row() {
    begin action_list_follows_the_highlighted_row
    install_defaults && finish 0 || return 1
    yadsmoke_start_app "$WS" "$WS/second.log"
    yadsmoke_answer "ReShade" Down Return &&
        yadsmoke_answer "ReShade - Select Game" Return &&
        yadsmoke_answer "ReShade - Uninstall Complete" Return && finish 0 || return 1
    [[ ! -e $GAME_BIN/dxgi.dll && ! -L $GAME_BIN/dxgi.dll ]] || { echo "ReShade was not uninstalled" >&2; return 1; }
    [[ -z $(ls "$STATE_DIR" 2>/dev/null) ]] || { echo "state was kept" >&2; return 1; }
}

scenario_update_all_ends_with_a_confirmation() {
    begin update_all_ends_with_a_confirmation
    install_defaults && finish 0 || return 1
    yadsmoke_start_app "$WS" "$WS/second.log"
    yadsmoke_answer "ReShade" Down Down Return &&
        yadsmoke_answer "ReShade - Update Complete" Return && finish 0 || return 1
    grep -q 'Batch update complete: 1 game' "$WS/second.log" || { echo "no game was updated" >&2; return 1; }
}

scenario_fatal_errors_are_shown_in_a_dialog() {
    begin fatal_errors_are_shown_in_a_dialog SHADER_REPOS=';' -- --app-id=999999
    yadsmoke_answer "ReShade" Return &&
        yadsmoke_answer "ReShade - Error" Return && finish 1 || return 1
    grep -q "Could not find a detected Steam game" "$LOG" || { echo "unexpected error text" >&2; return 1; }
}

SCENARIOS=(
    install_with_defaults
    cancel_at_the_first_dialog
    cancel_at_the_game_picker
    game_with_markup_characters_in_its_name
    unsupported_dll_name_is_rejected
    no_shader_packs_selected
    shader_picker_select_all_and_none
    shader_picker_select_none_installs_no_packs
    failed_shader_download_offers_a_retry
    action_list_follows_the_highlighted_row
    update_all_ends_with_a_confirmation
    fatal_errors_are_shown_in_a_dialog
)

main() {
    local _tool _missing=() _name _failed=0 _wanted=("$@")

    for _tool in yad Xvfb xdotool; do
        command -v "$_tool" >/dev/null || _missing+=("$_tool")
    done
    if (( ${#_missing[@]} > 0 )); then
        printf 'Missing required tools: %s\n' "${_missing[*]}" >&2
        return 2
    fi
    (( ${#_wanted[@]} > 0 )) || _wanted=("${SCENARIOS[@]}")

    SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/reshade-yad-smoke.XXXXXX")"
    trap 'yadsmoke_finish "$SMOKE_ROOT"' EXIT
    trap 'exit 130' INT TERM
    printf 'Smoke workspace: %s\n' "$SMOKE_ROOT"
    yadsmoke_display_start || return 2

    for _name in "${_wanted[@]}"; do
        if declare -F "scenario_$_name" >/dev/null && "scenario_$_name"; then
            printf 'PASS | %s\n' "$_name"
        else
            printf 'FAIL | %s\n' "$_name"
            _failed=$((_failed + 1))
            yadsmoke_abort_app
        fi
    done

    if (( _failed == 0 )); then
        printf 'SMOKE_RESULT=PASS\n'
        return 0
    fi
    printf 'SMOKE_RESULT=FAIL (%s scenario(s) failed)\n' "$_failed"
    return 1
}

main "$@"
