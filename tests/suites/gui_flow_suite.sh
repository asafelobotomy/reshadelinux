#!/bin/bash
# shellcheck disable=SC2030,SC2031  # settings are changed inside subshells on purpose
# shellcheck disable=SC2317,SC2329  # test functions and stubs are invoked indirectly
# shellcheck disable=SC2034  # variables are set for the code under test
# shellcheck disable=SC2016  # the fake programs are written as literal shell text

# What a user of the graphical backend sees at the end of each flow. A desktop launch has no
# terminal (the desktop entry says Terminal=false), so anything only printed is never seen.

# Replace ui_msgbox with a recorder: one "title|text" line per dialog.
_record_msgboxes() {
    _MSGBOX_LOG="$1"
    ui_msgbox() { printf '%s|%s\n' "$1" "$2" >> "$_MSGBOX_LOG"; }
}

_seed_one_installed_game() {
    local _game_dir="$TEST_TEMP_DIR/gui-batch-game"

    mkdir -p "$MAIN_PATH/game-state" "$RESHADE_PATH/latest" "$_game_dir"
    touch "$RESHADE_PATH/latest/ReShade64.dll" "$RESHADE_PATH/latest/ReShade32.dll" "$MAIN_PATH/d3dcompiler_47.dll.64"
    export SHADER_REPOS="https://example.com/a|alpha"
    export RESHADE_VERSION=latest
    init_test_runtime_defaults
    create_mock_shader_repo "alpha"
    cat > "$MAIN_PATH/game-state/3000.state" <<STATE
dll=dxgi
arch=64
gamePath=$_game_dir
selected_repos=alpha
app_id=3000
STATE
}

test_update_all_ends_with_a_dialog_for_the_graphical_backend() {
    local _log="$TEST_TEMP_DIR/msgbox.log"

    _seed_one_installed_game
    (
        _record_msgboxes "$_log"
        _UI_BACKEND=yad
        _BATCH_UPDATE=1
        maybeHandleBatchUpdate
    ) >/dev/null 2>&1

    [[ $(wc -l < "$_log") -eq 1 ]]
    grep -q '^ReShade - Update Complete|Updated 1 game(s)' "$_log"
}

test_update_all_stays_terminal_only_for_the_cli_backend() {
    local _log="$TEST_TEMP_DIR/msgbox.log"

    _seed_one_installed_game
    (
        _record_msgboxes "$_log"
        _UI_BACKEND=cli
        _BATCH_UPDATE=1
        maybeHandleBatchUpdate
    ) >/dev/null 2>&1

    [[ ! -e $_log ]]
}

test_update_all_dialog_reports_skipped_games() {
    local _log="$TEST_TEMP_DIR/msgbox.log"

    _seed_one_installed_game
    rm -f "$RESHADE_PATH/latest/ReShade64.dll"
    (
        _record_msgboxes "$_log"
        _UI_BACKEND=yad
        _BATCH_UPDATE=1
        maybeHandleBatchUpdate
    ) >/dev/null 2>&1

    grep -q 'Updated 0 game(s)' "$_log"
    grep -q 'skipped 1' "$_log"
}

_seed_uninstallable_game() {
    local _game="$TEST_TEMP_DIR/gui-uninstall-game"

    _prepare_game_link_environment "$_game"
    linkGameFilesForInstall >/dev/null
    CLI_GAME_PATH="$_game"
    CLI_GAME_PATH_SET=1
    CLI_APP_ID=""
    CLI_APP_ID_SET=0
    _SEEDED_GAME="$_game"
}

test_uninstall_ends_with_a_dialog_naming_the_game_folder_for_the_graphical_backend() {
    local _log="$TEST_TEMP_DIR/msgbox.log" _game

    _seed_uninstallable_game
    _game="$_SEEDED_GAME"
    (
        _record_msgboxes "$_log"
        _UI_BACKEND=yad
        performDirectXUninstall
    ) >/dev/null 2>&1

    [[ $(wc -l < "$_log") -eq 1 ]]
    grep -q '^ReShade - Uninstall Complete|' "$_log"
    grep -qF "$_game" "$_log"
    grep -q 'WINEDLLOVERRIDES' "$_log"
}

test_terminal_backends_do_not_get_a_completion_dialog_they_would_have_to_dismiss() {
    local _log="$TEST_TEMP_DIR/msgbox.log" _backend

    for _backend in whiptail dialog; do
        _seed_one_installed_game
        (
            _record_msgboxes "$_log"
            _UI_BACKEND="$_backend"
            _BATCH_UPDATE=1
            maybeHandleBatchUpdate
        ) >/dev/null 2>&1
        [[ ! -e $_log ]] || { echo "$_backend got an update dialog" >&2; return 1; }
    done

    _seed_uninstallable_game
    (
        _record_msgboxes "$_log"
        _UI_BACKEND=whiptail
        performDirectXUninstall
    ) >/dev/null 2>&1
    [[ ! -e $_log ]]
}

test_uninstall_stays_terminal_only_for_the_cli_backend() {
    local _log="$TEST_TEMP_DIR/msgbox.log"

    _seed_uninstallable_game
    (
        _record_msgboxes "$_log"
        _UI_BACKEND=cli
        performDirectXUninstall
    ) >/dev/null 2>&1

    [[ ! -e $_log ]]
}

run_gui_flow_tests() {
    echo -e "${BLUE}Graphical Flow Tests${NC}"
    run_test "Update-all ends with a dialog on the GUI backend" test_update_all_ends_with_a_dialog_for_the_graphical_backend
    run_test "Update-all stays terminal-only on the CLI backend" test_update_all_stays_terminal_only_for_the_cli_backend
    run_test "Update-all dialog reports skipped games" test_update_all_dialog_reports_skipped_games
    run_test "Uninstall ends with a dialog on the GUI backend" test_uninstall_ends_with_a_dialog_naming_the_game_folder_for_the_graphical_backend
    run_test "Uninstall stays terminal-only on the CLI backend" test_uninstall_stays_terminal_only_for_the_cli_backend
    run_test "Terminal backends get no completion dialog" test_terminal_backends_do_not_get_a_completion_dialog_they_would_have_to_dismiss
    echo ""
}
