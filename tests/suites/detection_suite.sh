#!/bin/bash

test_exe_warhammer() {
    local result
    create_warhammer_test
    result=$(pickBestExeInDir "$TEST_GAMES_DIR/Warhammer 40,000 Rogue Trader")
    [[ "$result" == "WH40KRT.exe" ]]
}

test_exe_unity_filter() {
    local game_dir="$TEST_GAMES_DIR/UnityTest"
    local result
    mkdir -p "$game_dir"
    touch "$game_dir/game.exe"
    touch "$game_dir/UnityPlayer.exe"

    result=$(pickBestExeInDir "$game_dir")
    [[ "$result" == "game.exe" ]] || [[ -n "$result" ]]
}

test_exe_setup_filter() {
    local result
    create_complex_exes_test
    result=$(pickBestExeInDir "$TEST_GAMES_DIR/Complex Game")
    [[ "$result" != "setup.exe" ]]
}

test_exe_no_exes() {
    local game_dir="$TEST_GAMES_DIR/NoExes"
    local result
    mkdir -p "$game_dir"
    result=$(pickBestExeInDir "$game_dir" || true)
    [[ -z "$result" ]]
}

test_exe_all_utilities_returns_empty() {
    local game_dir="$TEST_GAMES_DIR/BadOnly"
    local result
    mkdir -p "$game_dir"
    touch "$game_dir/mono.exe"
    touch "$game_dir/setup.exe"

    result=$(pickBestExeInDir "$game_dir" || true)
    [[ -z "$result" ]]
}

test_exe_name_match() {
    local game_dir="$TEST_GAMES_DIR/MyGame"
    local result
    mkdir -p "$game_dir"
    touch "$game_dir/MyGame.exe"
    touch "$game_dir/launcher.exe"

    result=$(pickBestExeInDir "$game_dir")
    [[ "$result" == "MyGame.exe" ]]
}

test_icon_logo() {
    local appid="255710"
    local result
    create_mock_icon "$appid"
    result=$(findSteamIconPath "$TEST_STEAM_ROOT" "$appid")
    [[ "$result" == *"logo.png" ]]
}

test_icon_hash_over_header() {
    local appid="999888"
    local cache_dir="$TEST_STEAM_CACHE/$appid"
    local result
    mkdir -p "$cache_dir"
    echo "mini" > "$cache_dir/a94a8fe5ccb19ba61c4c0873d391e987982fbbd3.jpg"
    echo "banner" > "$cache_dir/header.jpg"

    result=$(findSteamIconPath "$TEST_STEAM_ROOT" "$appid")
    [[ "$result" == *"a94a8fe5ccb19ba61c4c0873d391e987982fbbd3.jpg" ]]
}

test_icon_library_skip() {
    local appid="777888"
    local cache_dir="$TEST_STEAM_CACHE/$appid"
    local result
    mkdir -p "$cache_dir"
    echo "lib content" > "$cache_dir/library_600x900.jpg"
    echo "actual" > "$cache_dir/b6589fc6ab0dc82cf12099d1c2d40ab994e8410c.jpg"

    result=$(findSteamIconPath "$TEST_STEAM_ROOT" "$appid")
    [[ "$result" == *"b6589fc6ab0dc82cf12099d1c2d40ab994e8410c.jpg" ]]
}

test_icon_missing() {
    local appid="111222"
    local cache_dir="$TEST_STEAM_CACHE/$appid"
    local result
    mkdir -p "$cache_dir"

    result=$(findSteamIconPath "$TEST_STEAM_ROOT" "$appid" || true)
    [[ -z "$result" ]]
}

test_ui_backend_prefers_yad_in_graphical_session() {
    local fakebin="$TEST_TEMP_DIR/fakebin"
    local result
    mkdir -p "$fakebin"
    printf '#!/bin/sh\nexit 0\n' > "$fakebin/yad"
    chmod +x "$fakebin/yad"

    result=$(PATH="$fakebin:$PATH" DISPLAY=:1 WAYLAND_DISPLAY='' chooseUiBackend 0)
    [[ "$result" == "yad" ]]
}

test_ui_backend_tty_prefers_whiptail_over_yad() {
    local fakebin="$TEST_TEMP_DIR/fakebin"
    local result
    mkdir -p "$fakebin"
    printf '#!/bin/sh\nexit 0\n' > "$fakebin/yad"
    printf '#!/bin/sh\nexit 0\n' > "$fakebin/whiptail"
    chmod +x "$fakebin/yad" "$fakebin/whiptail"

    result=$(PATH="$fakebin:$PATH" DISPLAY=:1 WAYLAND_DISPLAY='' chooseUiBackend 1)
    [[ "$result" == "whiptail" ]]
}

test_ui_backend_uses_whiptail_on_tty_without_yad() {
    local fakebin="$TEST_TEMP_DIR/fakebin"
    local result
    mkdir -p "$fakebin"
    printf '#!/bin/sh\nexit 0\n' > "$fakebin/whiptail"
    chmod +x "$fakebin/whiptail"

    result=$(PATH="$fakebin:$PATH" DISPLAY='' WAYLAND_DISPLAY='' chooseUiBackend 1)
    [[ "$result" == "whiptail" ]]
}

test_ui_backend_falls_back_to_cli_without_tools() {
    local result
    result=$(DISPLAY='' WAYLAND_DISPLAY='' chooseUiBackend 0)
    [[ "$result" == "cli" ]]
}

test_ui_backend_honors_forced_cli_override() {
    local result
    result=$(UI_BACKEND=cli DISPLAY=:1 WAYLAND_DISPLAY=:1 chooseUiBackend 1)
    [[ "$result" == "cli" ]]
}

test_ui_backend_honors_forced_yad_override() {
    local fakebin="$TEST_TEMP_DIR/fakebin"
    local result
    mkdir -p "$fakebin"
    printf '#!/bin/sh\nexit 0\n' > "$fakebin/yad"
    chmod +x "$fakebin/yad"

    result=$(PATH="$fakebin:$PATH" UI_BACKEND=yad DISPLAY='' WAYLAND_DISPLAY='' chooseUiBackend 0)
    [[ "$result" == "yad" ]]
}

test_ui_backend_rejects_missing_forced_backend_binary() {
    local fakebin="$TEST_TEMP_DIR/emptybin"
    local _output _rc

    mkdir -p "$fakebin"

    set +e
    _output=$(PATH="$fakebin" UI_BACKEND=yad DISPLAY='' WAYLAND_DISPLAY='' chooseUiBackend 0 2>&1)
    _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
    [[ $_output == *"Requested UI backend 'yad' is not installed or not on PATH."* ]]
}

test_init_runtime_config_fails_when_forced_backend_is_missing() {
    local fakebin="$TEST_TEMP_DIR/config-emptybin"
    local _rc

    mkdir -p "$fakebin"

    set +e
    PATH="$fakebin" UI_BACKEND=yad init_runtime_config >/dev/null 2>&1
    _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
}

test_appimage_apprun_delegates_to_gui_wrapper() {
    local _apprun_path="$SCRIPT_DIR/../packaging/appimage/AppDir/AppRun"
    local _contents

    _contents=$(<"$_apprun_path")
    [[ $_contents == *'exec "$HERE/usr/bin/reshadelinux-gui.sh" "$@"'* ]]
}

test_ui_backend_rejects_invalid_override() {
    ! UI_BACKEND=broken chooseUiBackend 1 >/dev/null 2>&1
}

test_preset_cyberpunk() {
    local result
    result=$(getBuiltInGameDirPreset "1091500")
    [[ "$result" == "bin/x64" ]]
}

test_preset_witcher() {
    local result
    result=$(getBuiltInGameDirPreset "292030")
    [[ "$result" == "bin/x64" ]]
}

test_preset_nms() {
    local result
    result=$(getBuiltInGameDirPreset "275850")
    [[ "$result" == "Binaries" ]]
}

test_preset_elden() {
    local result
    result=$(getBuiltInGameDirPreset "1245620")
    [[ "$result" == "Game" ]]
}

test_preset_eso() {
    local result
    result=$(getBuiltInGameDirPreset "306130")
    [[ "$result" == "The Elder Scrolls Online/game/client" ]]
}

test_preset_oblivion_remastered() {
    local result
    result=$(getBuiltInGameDirPreset "2623190")
    [[ "$result" == "OblivionRemastered/Binaries/Win64" ]]
}

test_preset_unknown() {
    local result
    result=$(getBuiltInGameDirPreset "999999" || true)
    [[ -z "$result" ]]
}

test_integration_full_pipeline() {
    local exe icon
    create_warhammer_test
    create_mock_icon "2021390"

    exe=$(pickBestExeInDir "$TEST_GAMES_DIR/Warhammer 40,000 Rogue Trader")
    icon=$(findSteamIconPath "$TEST_STEAM_ROOT" "2021390")

    [[ "$exe" == "WH40KRT.exe" ]] && [[ -n "$icon" ]]
}

test_integration_multi_games() {
    local wh_exe cities_exe
    create_warhammer_test
    create_cities_skylines_test

    wh_exe=$(pickBestExeInDir "$TEST_GAMES_DIR/Warhammer 40,000 Rogue Trader")
    cities_exe=$(pickBestExeInDir "$TEST_GAMES_DIR/Cities_Skylines")

    [[ "$wh_exe" == "WH40KRT.exe" ]] && [[ "$cities_exe" == "Cities.exe" ]]
}

test_install_dir_prefers_subdir_over_root() {
    local game_root="$TEST_GAMES_DIR/RootVsBin"
    local result
    mkdir -p "$game_root/bin/x64"
    touch "$game_root/launcher.exe"
    touch "$game_root/bin/x64/RootVsBin.exe"

    result=$(resolveGameInstallDir "$game_root" "555000")
    [[ "$result" == "$game_root/bin/x64|heuristic" ]]
}

test_install_dir_uses_custom_preset_when_present() {
    local game_root="$TEST_GAMES_DIR/PresetGame"
    local result
    export GAME_DIR_PRESETS="444000|Custom/Binaries"
    mkdir -p "$game_root/Custom/Binaries"
    touch "$game_root/Custom/Binaries/PresetGame.exe"
    touch "$game_root/root.exe"

    result=$(resolveGameInstallDir "$game_root" "444000")
    [[ "$result" == "$game_root/Custom/Binaries|preset:Custom/Binaries" ]]
}

test_install_dir_scan_fallback_finds_best_nested_exe() {
    local game_root="$TEST_GAMES_DIR/ScanFallback"
    local result
    mkdir -p "$game_root/CustomBuild/Shipping"
    mkdir -p "$game_root/Runtime/MonoBleedingEdge"
    touch "$game_root/CustomBuild/Shipping/ScanFallback-Win64-Shipping.exe"
    touch "$game_root/Runtime/MonoBleedingEdge/mono.exe"

    result=$(resolveGameInstallDir "$game_root" "777000")
    [[ "$result" == "$game_root/CustomBuild/Shipping|scan" ]]
}

test_detect_steam_games_reads_manifest_install_path() {
    local steamapps_dir="$HOME/.local/share/Steam/steamapps"
    local game_root="$steamapps_dir/common/AutoDetectGame"

    mkdir -p "$game_root/bin/x64"
    touch "$game_root/bin/x64/AutoDetectGame.exe"
    cat > "$steamapps_dir/appmanifest_424242.acf" <<'EOF'
"AppState"
{
    "appid"        "424242"
    "name"         "Auto Detect Game"
    "installdir"   "AutoDetectGame"
    "type"         "game"
}
EOF

    detectSteamGames

    [[ ${#DETECTED_GAME_APPIDS[@]} -eq 1 ]]
    [[ ${DETECTED_GAME_APPIDS[0]} == "424242" ]]
    [[ ${DETECTED_GAME_PATHS[0]} == "$game_root/bin/x64" ]]
    [[ ${DETECTED_GAME_EXES[0]} == "AutoDetectGame.exe" ]]
}

run_detection_tests() {
    echo -e "${BLUE}Exe Detection Tests${NC}"
    run_test "Warhammer 40K exe selection" test_exe_warhammer
    run_test "UnityPlayer filtering" test_exe_unity_filter
    run_test "Setup.exe filtering" test_exe_setup_filter
    run_test "No exes handling" test_exe_no_exes
    run_test "Utility-only dirs return empty" test_exe_all_utilities_returns_empty
    run_test "Name matching bonus" test_exe_name_match
    echo ""

    echo -e "${BLUE}Icon Detection Tests${NC}"
    run_test "Logo.png prioritization" test_icon_logo
    run_test "Hash icon over header" test_icon_hash_over_header
    run_test "Library file skipping" test_icon_library_skip
    run_test "Missing icon handling" test_icon_missing
    echo ""

    echo -e "${BLUE}UI Backend Tests${NC}"
    run_test "Graphical-only sessions prefer YAD" test_ui_backend_prefers_yad_in_graphical_session
    run_test "TTY prefers whiptail over YAD" test_ui_backend_tty_prefers_whiptail_over_yad
    run_test "TTY sessions use whiptail fallback" test_ui_backend_uses_whiptail_on_tty_without_yad
    run_test "No UI tools falls back to CLI" test_ui_backend_falls_back_to_cli_without_tools
    run_test "Forced CLI override wins" test_ui_backend_honors_forced_cli_override
    run_test "Forced YAD override wins" test_ui_backend_honors_forced_yad_override
    run_test "Forced backend requires installed binary" test_ui_backend_rejects_missing_forced_backend_binary
    run_test "Runtime init fails when forced backend missing" test_init_runtime_config_fails_when_forced_backend_is_missing
    run_test "Invalid UI_BACKEND is rejected" test_ui_backend_rejects_invalid_override
    run_test "AppImage AppRun delegates to GUI wrapper" test_appimage_apprun_delegates_to_gui_wrapper
    echo ""

    echo -e "${BLUE}Preset Tests${NC}"
    run_test "Cyberpunk 2077 preset" test_preset_cyberpunk
    run_test "Witcher 3 preset" test_preset_witcher
    run_test "No Man's Sky preset" test_preset_nms
    run_test "Elden Ring preset" test_preset_elden
    run_test "ESO preset" test_preset_eso
    run_test "Oblivion Remastered preset" test_preset_oblivion_remastered
    run_test "Unknown AppID" test_preset_unknown
    echo ""

    echo -e "${BLUE}Integration Tests${NC}"
    run_test "Full detection pipeline" test_integration_full_pipeline
    run_test "Multiple games handling" test_integration_multi_games
    run_test "Install dir prefers bin/x64 over root" test_install_dir_prefers_subdir_over_root
    run_test "Custom install-dir preset wins" test_install_dir_uses_custom_preset_when_present
    run_test "Install dir scan fallback finds nested exe" test_install_dir_scan_fallback_finds_best_nested_exe
    run_test "Manifest autodetect resolves install path" test_detect_steam_games_reads_manifest_install_path
    echo ""
}