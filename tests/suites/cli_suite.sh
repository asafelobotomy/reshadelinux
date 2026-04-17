#!/bin/bash

test_cli_argument_parser_sets_explicit_overrides() {
    local _game_dir="$TEST_TEMP_DIR/cli-parser"
    mkdir -p "$_game_dir"

    parseCliArgs \
        --cli \
        --game-path="$_game_dir" \
        --app-id=123456 \
        --dll-override=dxgi \
        --shader-repos=beta,alpha

    [[ $_BATCH_UPDATE -eq 0 ]]
    [[ ${UI_BACKEND:-} == cli ]]
    [[ ${CLI_GAME_PATH_SET:-0} -eq 1 ]]
    [[ $CLI_GAME_PATH == "$_game_dir" ]]
    [[ ${CLI_APP_ID_SET:-0} -eq 1 ]]
    [[ $CLI_APP_ID == 123456 ]]
    [[ ${CLI_DLL_OVERRIDE_SET:-0} -eq 1 ]]
    [[ $CLI_DLL_OVERRIDE == dxgi ]]
    [[ ${CLI_SHADER_REPOS_SET:-0} -eq 1 ]]
    [[ $CLI_SHADER_REPOS == beta,alpha ]]
}

test_cli_validation_normalizes_shader_repo_selection() {
    export SHADER_REPOS="https://example.com/a|alpha;https://example.com/b|beta"

    parseCliArgs --cli --shader-repos=' beta , alpha , beta '
    init_runtime_config
    validateCliArgs

    [[ $CLI_SHADER_REPOS == alpha,beta ]]
}

test_cli_validation_rejects_mixed_ui_backend_flags() {
    local _output _rc

    set +e
    _output=$( (
        parseCliArgs --cli --ui-backend=dialog
        init_runtime_config
        validateCliArgs
    ) 2>&1 )
    _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
    [[ $_output == *"Use either --cli or --ui-backend=<backend>, not both."* ]]
}

test_cli_validation_rejects_update_all_with_game_specific_flags() {
    local _game_dir="$TEST_TEMP_DIR/cli-update-all-conflict"
    local _output _rc
    mkdir -p "$_game_dir"

    set +e
    _output=$( (
        parseCliArgs --update-all --game-path="$_game_dir" --app-id=123456 --dll-override=dxgi
        init_runtime_config
        validateCliArgs
    ) 2>&1 )
    _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
    [[ $_output == *"--update-all cannot be combined with --game-path, --app-id, or --dll-override."* ]]
}

test_cli_ui_backend_flag_is_case_insensitive() {
    parseCliArgs --ui-backend=CLI
    init_runtime_config
    validateCliArgs

    [[ $_UI_BACKEND == cli ]]
}

test_cli_validation_normalizes_uppercase_dll_override() {
    parseCliArgs --cli --dll-override=DXGI.dll
    init_runtime_config
    validateCliArgs

    [[ $CLI_DLL_OVERRIDE == dxgi ]]
}

test_cli_validation_rejects_unknown_shader_repo() {
    local _output _rc
    export SHADER_REPOS="https://example.com/a|alpha;https://example.com/b|beta"

    set +e
    _output=$( (
        parseCliArgs --cli --shader-repos=gamma
        init_runtime_config
        validateCliArgs
    ) 2>&1 )
    _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
    [[ $_output == *"Unknown shader repository: gamma"* ]]
}

test_cli_game_path_bypasses_detection() {
    local _game_dir="$TEST_TEMP_DIR/cli-game-path"
    mkdir -p "$_game_dir"
    touch "$_game_dir/Game.exe"

    parseCliArgs --cli --game-path="$_game_dir"
    init_runtime_config
    validateCliArgs

    detectSteamGames() {
        printf 'unexpected detection\n' >&2
        return 1
    }

    getGamePath

    [[ $gamePath == "$_game_dir" ]]
    [[ -z ${_selectedAppId:-} ]]
}

test_cli_game_path_can_persist_explicit_app_id() {
    local _game_dir="$TEST_TEMP_DIR/cli-game-path-app-id"
    mkdir -p "$_game_dir"
    touch "$_game_dir/Game.exe"

    parseCliArgs --cli --game-path="$_game_dir" --app-id=555000
    init_runtime_config
    validateCliArgs

    detectSteamGames() {
        printf 'unexpected detection\n' >&2
        return 1
    }

    getGamePath

    [[ $gamePath == "$_game_dir" ]]
    [[ ${_selectedAppId:-} == 555000 ]]
}

test_cli_app_id_selects_detected_game() {
    local _game_dir="$TEST_TEMP_DIR/cli-app-id"
    mkdir -p "$_game_dir"
    touch "$_game_dir/Game.exe"

    parseCliArgs --cli --app-id=555000
    init_runtime_config
    validateCliArgs

    detectSteamGames() {
        DETECTED_GAME_NAMES=("CLI Pick")
        DETECTED_GAME_APPIDS=("555000")
        DETECTED_GAME_PATHS=("$_game_dir")
        DETECTED_GAME_EXES=("Game.exe")
        DETECTED_GAME_ICONS=("")
        DETECTED_GAME_REASONS=("manual")
    }

    promptGamePathManual() {
        printf 'unexpected manual prompt\n' >&2
        return 1
    }

    getGamePath

    [[ $gamePath == "$_game_dir" ]]
    [[ ${_selectedAppId:-} == 555000 ]]
}

test_cli_version_flag_prints_current_version() {
    local _output _rc

    set +e
    _output=$( (
        SCRIPT_VERSION=9.9.9
        parseCliArgs --version
    ) 2>&1 )
    _rc=$?
    set -e

    [[ $_rc -eq 0 ]]
    [[ $_output == *"9.9.9"* ]]
}

test_cli_list_shader_repos_prints_configured_repo_labels() {
    local _output _rc
    export SHADER_REPOS="https://github.com/demo/alpha|alpha||Alpha Collection|Alpha repo;https://github.com/demo/beta|beta|main|Beta Collection|Beta repo"

    parseCliArgs --list-shader-repos
    init_runtime_config
    validateCliArgs

    set +e
    _output=$( ( handleCliInfoArgs ) 2>&1 )
    _rc=$?
    set -e

    [[ $_rc -eq 0 ]]
    [[ $_output == *"Configured shader repositories:"* ]]
    [[ $_output == *$'alpha\tAlpha Collection by demo | Alpha repo'* ]]
    [[ $_output == *$'beta\tBeta Collection by demo | Beta repo'* ]]
}

run_cli_tests() {
    echo -e "${BLUE}CLI Flow Tests${NC}"
    run_test "CLI parser sets explicit overrides" test_cli_argument_parser_sets_explicit_overrides
    run_test "CLI validation normalizes shader repo selection" test_cli_validation_normalizes_shader_repo_selection
    run_test "CLI validation rejects mixed UI backend flags" test_cli_validation_rejects_mixed_ui_backend_flags
    run_test "CLI validation rejects update-all game-specific conflicts" test_cli_validation_rejects_update_all_with_game_specific_flags
    run_test "CLI UI backend flag is case-insensitive" test_cli_ui_backend_flag_is_case_insensitive
    run_test "CLI validation normalizes uppercase DLL override" test_cli_validation_normalizes_uppercase_dll_override
    run_test "CLI validation rejects unknown shader repo" test_cli_validation_rejects_unknown_shader_repo
    run_test "CLI game path bypasses detection" test_cli_game_path_bypasses_detection
    run_test "CLI game path can persist explicit App ID" test_cli_game_path_can_persist_explicit_app_id
    run_test "CLI App ID selects detected game" test_cli_app_id_selects_detected_game
    run_test "CLI version flag prints current version" test_cli_version_flag_prints_current_version
    run_test "CLI list shader repos prints configured labels" test_cli_list_shader_repos_prints_configured_repo_labels
    echo ""
}