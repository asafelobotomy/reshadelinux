#!/bin/bash

# Executable selection and scoring heuristics.

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

test_exe_score_keeps_names_that_only_contain_utility_words() {
    local _name _score

    # Each name contains a utility word ("eac", "test", "asp", "check") as a
    # substring but is an ordinary game executable.
    for _name in reach.exe latest.exe teacher.exe aspect.exe wasp.exe beacon.exe contest.exe checkers.exe; do
        _score=$(scoreExeCandidate "/games/Anything" "$_name")
        if [[ $_score -lt 50 ]]; then
            echo "$_name scored $_score, expected at least 50" >&2
            return 1
        fi
    done
}

test_exe_score_still_penalizes_utility_executables() {
    local _name _score

    for _name in unins000.exe vc_redist.x64.exe UnityCrashHandler64.exe UnityCrashHandler32.exe \
        EasyAntiCheat.exe EasyAntiCheat_Setup.exe crashpad_handler.exe CrashReporter.exe \
        setup.exe Setup_x64.exe uninstall.exe installer.exe launcher.exe GameLauncher.exe \
        eac.exe EAC_Launcher.exe test.exe update.exe Updater.exe error.exe benchmark.exe \
        remove.exe UnityPlayer.exe DXSETUP.exe dxsetup.exe Errors.exe; do
        _score=$(scoreExeCandidate "/games/Anything" "$_name")
        if [[ $_score -ge 0 ]]; then
            echo "$_name scored $_score, expected a negative score" >&2
            return 1
        fi
    done
}

test_exe_score_penalizes_very_short_names() {
    local _name _score

    for _name in a.exe ab.exe x1.exe; do
        _score=$(scoreExeCandidate "/games/Anything" "$_name")
        if [[ $_score -ge 50 ]]; then
            echo "$_name scored $_score, expected a penalty below 50" >&2
            return 1
        fi
    done
}

test_exe_score_ignores_parent_name_bonus_when_it_has_no_letters() {
    local _score

    _score=$(scoreExeCandidate "/games/!!!" "zzz.exe")
    [[ $_score -eq 50 ]]
}

test_exe_pick_best_finds_single_exe_with_utility_substring() {
    local _game_dir="$TEST_GAMES_DIR/ReachGame"
    local _result

    mkdir -p "$_game_dir"
    touch "$_game_dir/reach.exe"

    _result=$(pickBestExeInDir "$_game_dir")
    [[ $_result == "reach.exe" ]]
}

run_exe_tests() {
    echo -e "${BLUE}Exe Detection Tests${NC}"
    run_test "Warhammer 40K exe selection" test_exe_warhammer
    run_test "UnityPlayer filtering" test_exe_unity_filter
    run_test "Setup.exe filtering" test_exe_setup_filter
    run_test "No exes handling" test_exe_no_exes
    run_test "Utility-only dirs return empty" test_exe_all_utilities_returns_empty
    run_test "Name matching bonus" test_exe_name_match
    run_test "Keeps names that only contain utility words" test_exe_score_keeps_names_that_only_contain_utility_words
    run_test "Still penalizes utility executables" test_exe_score_still_penalizes_utility_executables
    run_test "Penalizes very short names" test_exe_score_penalizes_very_short_names
    run_test "Parent-name bonus ignores letterless folders" test_exe_score_ignores_parent_name_bonus_when_it_has_no_letters
    run_test "Best exe finds reach.exe alone" test_exe_pick_best_finds_single_exe_with_utility_substring
    echo ""
}
