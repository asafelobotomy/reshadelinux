#!/bin/bash
# shellcheck disable=SC2317,SC2329  # test functions and stubs are invoked indirectly
# shellcheck disable=SC2034  # variables are set for the code under test
# shellcheck disable=SC2154  # variables are assigned by the code under test
# shellcheck disable=SC2030,SC2031,SC2123  # settings, PATH included, are changed inside subshells on purpose

# --no-input, --dry-run, --quiet, --json, --uninstall and the exit statuses, mostly by running
# the real entrypoint against the isolated test home. None of these runs reaches the network.

# Run reshadelinux.sh with no terminal and no display. stdout goes to $_OUT, stderr to $_ERR,
# and the exit status to $_RC. A run that waits for input would hit the timeout (124).
_run_installer() {
    _OUT="$TEST_TEMP_DIR/out.txt"
    _ERR="$TEST_TEMP_DIR/err.txt"
    set +e
    env -u DISPLAY -u WAYLAND_DISPLAY -u UI_BACKEND -u UI_AUTO_CONFIRM \
        timeout 20 bash "$REPO_DIR/reshadelinux.sh" "$@" </dev/null >"$_OUT" 2>"$_ERR"
    _RC=$?
    set -e
}

_make_game_dir() {
    local _dir="$TEST_TEMP_DIR/games/$1"
    mkdir -p "$_dir"
    printf 'MZ' > "$_dir/game.exe"
    printf '%s\n' "$_dir"
}

# Link a game the way an install leaves it, with a state file, without downloading anything.
_fake_installed_game() {
    local _game="$1" _key

    mkdir -p "$RESHADE_PATH/6.8.0"
    touch "$RESHADE_PATH/6.8.0/ReShade64.dll" "$MAIN_PATH/d3dcompiler_47.dll.64"
    ln -s "$RESHADE_PATH/6.8.0/ReShade64.dll" "$_game/dxgi.dll"
    ln -s "$MAIN_PATH/d3dcompiler_47.dll.64" "$_game/d3dcompiler_47.dll"
    _key=$(buildGameInstallKey "" "$_game")
    writeGameState "$_key" "$_game" dxgi 64 "" ""
}

# The workspace after a run, to prove a dry run left it exactly as it was.
_snapshot_tree() {
    find "$MAIN_PATH" "$TEST_TEMP_DIR/games" -printf '%p %y %l\n' 2>/dev/null | sort
}

test_an_unknown_flag_is_a_usage_error() {
    _run_installer --frobnicate

    [[ $_RC -eq 2 ]]
    grep -q 'Unknown argument: --frobnicate' "$_ERR"
    grep -q '^Usage:' "$_ERR"
}

test_help_leads_with_examples_and_names_the_project_page() {
    _run_installer --help

    [[ $_RC -eq 0 ]]
    grep -q '^Examples:' "$_OUT"
    grep -q -- '--no-input' "$_OUT"
    grep -q 'https://github.com/asafelobotomy/reshadelinux' "$_OUT"
    grep -q '^Exit status:' "$_OUT"
}

test_conflicting_flags_are_usage_errors() {
    local _game
    _game=$(_make_game_dir conflict)

    _run_installer --update-all --uninstall
    [[ $_RC -eq 2 ]]
    _run_installer --json
    [[ $_RC -eq 2 ]]
    _run_installer --no-input --ui-backend=whiptail --game-path="$_game"
    [[ $_RC -eq 2 ]]
    _run_installer --uninstall --dll-override=dxgi --game-path="$_game"
    [[ $_RC -eq 2 ]]
}

test_an_invalid_ui_backend_stops_the_run() {
    local _game
    _game=$(_make_game_dir bad-backend)

    _run_installer --ui-backend=nonsense --no-input --game-path="$_game"
    [[ $_RC -eq 2 ]]
    grep -q "Invalid UI_BACKEND='nonsense'" "$_ERR"
    assert_fails grep -q 'Using CLI game path' "$_OUT"
}

test_a_missing_game_path_is_a_usage_error() {
    _run_installer --no-input --game-path="$TEST_TEMP_DIR/does-not-exist"

    [[ $_RC -eq 2 ]]
    grep -q 'does not exist' "$_ERR"
}

test_list_shader_repos_json_is_valid_and_carries_pins() {
    _run_installer --list-shader-repos --json

    [[ $_RC -eq 0 ]]
    python3 -I - "$_OUT" <<'PY'
import json, sys
repos = json.load(open(sys.argv[1]))
names = {r["name"]: r for r in repos}
assert len(repos) >= 60, len(repos)
sweetfx = names["sweetfx-shaders"]
assert sweetfx["uri"] == "https://github.com/CeeJayDK/SweetFX"
assert sweetfx["creator"] == "CeeJayDK"
assert len(sweetfx["commit"]) == 40
assert names["ann-reshade"]["requires"] == ["cshade"]
assert names["reshade-shaders"]["branch"] == "slim"
PY
}

test_json_strings_escape_quotes_backslashes_and_control_characters() {
    local _json

    _json=$(_jsonString $'say "hi"\\path\ttab\x01end')

    python3 -I -c 'import json, sys; assert json.loads(sys.argv[1]) == "say \"hi\"\\path\ttab\x01end"' "$_json"
}

test_no_input_without_a_game_fails_instead_of_waiting() {
    _run_installer --no-input

    [[ $_RC -eq 2 ]]
    grep -q -- '--game-path' "$_ERR"
}

test_no_input_uses_the_detected_dll_and_stored_shader_selection() {
    local _game
    _game=$(_make_game_dir no-input)

    _run_installer --no-input --dry-run --game-path="$_game"

    [[ $_RC -eq 0 ]]
    grep -Eq 'Detected (32|64)-bit game, using [a-z0-9]+\.dll \(--no-input\)' "$_OUT"
    grep -Eq 'would link [a-z0-9]+\.dll -> ' "$_OUT"
    grep -q 'reshade-shaders: would clone (pinned ' "$_OUT"
}

test_dry_run_install_describes_the_plan_and_changes_nothing() {
    local _game _before
    _game=$(_make_game_dir dry-install)
    _before=$(_snapshot_tree)

    _run_installer --no-input --dry-run --game-path="$_game" --dll-override=dxgi --shader-repos=sweetfx-shaders

    [[ $_RC -eq 0 ]]
    grep -q '^Dry run: nothing was changed.' "$_OUT"
    grep -q 'would link dxgi.dll' "$_OUT"
    grep -q 'ReShade.ini: would be created' "$_OUT"
    grep -q 'sweetfx-shaders: would clone (pinned ' "$_OUT"
    grep -q 'Launch option: WINEDLLOVERRIDES="d3dcompiler_47=n;dxgi=n,b" %command%' "$_OUT"
    [[ $(_snapshot_tree) == "$_before" ]]
}

test_dry_run_does_not_create_a_missing_workspace() {
    local _game
    _game=$(_make_game_dir dry-fresh)
    rm -rf "$MAIN_PATH"

    _run_installer --no-input --dry-run --game-path="$_game" --dll-override=dxgi --shader-repos=none

    [[ $_RC -eq 0 ]]
    [[ ! -e $MAIN_PATH ]]
}

test_dry_run_uninstall_lists_the_links_and_keeps_them() {
    local _game _before
    _game=$(_make_game_dir dry-uninstall)
    _fake_installed_game "$_game"
    _before=$(_snapshot_tree)

    _run_installer --no-input --dry-run --uninstall --game-path="$_game"

    [[ $_RC -eq 0 ]]
    grep -q 'would unlink dxgi.dll' "$_OUT"
    grep -q 'would unlink d3dcompiler_47.dll' "$_OUT"
    grep -q 'would delete its state file' "$_OUT"
    [[ $(_snapshot_tree) == "$_before" ]]
}

test_uninstall_flag_removes_reshade_without_asking() {
    local _game
    _game=$(_make_game_dir uninstall)
    _fake_installed_game "$_game"

    _run_installer --no-input --uninstall --game-path="$_game"

    [[ $_RC -eq 0 ]]
    [[ ! -e $_game/dxgi.dll && ! -L $_game/dxgi.dll ]]
    [[ ! -L $_game/d3dcompiler_47.dll ]]
    [[ -f $_game/game.exe ]]
    assert_fails compgen -G "$MAIN_PATH/game-state/*.state"
}

test_dry_run_update_all_lists_every_tracked_game() {
    local _game _before
    _game=$(_make_game_dir dry-batch)
    _fake_installed_game "$_game"
    _before=$(_snapshot_tree)

    _run_installer --dry-run --update-all

    [[ $_RC -eq 0 ]]
    grep -q "Would update .*: $_game" "$_OUT"
    grep -q 'would re-link dxgi.dll (64-bit)' "$_OUT"
    [[ $(_snapshot_tree) == "$_before" ]]
}

test_quiet_drops_progress_output_but_keeps_results_and_errors() {
    local _game
    _game=$(_make_game_dir quiet)

    _run_installer --quiet --no-input --dry-run --game-path="$_game" --dll-override=dxgi --shader-repos=none
    [[ $_RC -eq 0 ]]
    assert_fails grep -q 'ReShade installer/updater' "$_OUT"
    assert_fails grep -q 'Using CLI game path' "$_OUT"
    grep -q '^Dry run: nothing was changed.' "$_OUT"

    _run_installer --quiet --list-shader-repos
    grep -q '^Configured shader repositories:' "$_OUT"

    _run_installer --quiet --no-input --game-path="$TEST_TEMP_DIR/missing"
    [[ $_RC -eq 2 ]]
    grep -q 'does not exist' "$_ERR"
}

test_a_missing_program_exits_with_the_dependency_status() {
    local _rc

    set +e
    ( PATH="$TEST_TEMP_DIR/empty-bin"; _UI_BACKEND=cli; use_fatal_printErr
        checkRequiredExecutables 7z ) >/dev/null 2>&1
    _rc=$?
    set -e

    [[ $_rc -eq $EXIT_DEPENDENCY ]]
}

test_an_unreachable_reshade_site_exits_with_the_network_status() {
    local _rc

    set +e
    (
        export RESHADE_VERSION=latest FORCE_RESHADE_UPDATE_CHECK=1
        init_test_runtime_defaults
        use_fatal_printErr
        curl() { return 7; }
        ensureRequestedReshadeVersion
    ) >/dev/null 2>&1
    _rc=$?
    set -e

    [[ $_rc -eq $EXIT_NETWORK ]]
}

test_latest_falls_back_to_the_newest_pinned_build() {
    local _calls="$TEST_TEMP_DIR/downloads" _output

    _output=$( (
        export RESHADE_VERSION=latest FORCE_RESHADE_UPDATE_CHECK=1
        unset RESHADE_SETUP_SHA256 RESHADE_ALLOW_UNPINNED
        init_test_runtime_defaults
        pin_test_reshade_builds 6.8.0 6.8.0_Addon 6.7.3
        use_fatal_printErr
        curl() { printf '<a href="/downloads/ReShade_Setup_9.0.0.exe">x</a>'; }
        withProgress() { shift; "$@"; }
        downloadReshade() {
            printf '%s %s\n' "$1" "$2" >> "$_calls"
            mkdir -p "$RESHADE_PATH/$1"
            touch "$RESHADE_PATH/$1/ReShade64.dll" "$RESHADE_PATH/$1/ReShade32.dll"
        }
        ensureRequestedReshadeVersion
    ) 2>&1 )

    [[ $(<"$_calls") == "6.8.0 https://reshade.me/downloads/ReShade_Setup_6.8.0.exe" ]]
    [[ $_output == *"ReShade 9.0.0 is newer than the builds this installer has checksums for, so 6.8.0 is used"* ]]
}

test_an_unpinned_requested_version_is_refused_before_downloading() {
    local _calls="$TEST_TEMP_DIR/downloads" _rc

    set +e
    (
        export RESHADE_VERSION=5.0.0
        unset RESHADE_SETUP_SHA256 RESHADE_ALLOW_UNPINNED
        init_test_runtime_defaults
        UPDATE_RESHADE=0
        mkdir -p "$RESHADE_PATH/latest"
        touch "$RESHADE_PATH/latest/ReShade64.dll" "$RESHADE_PATH/latest/ReShade32.dll"
        pin_test_reshade_builds 6.8.0
        use_fatal_printErr
        curl() { return 7; }
        downloadReshade() { printf '%s\n' "$1" >> "$_calls"; }
        ensureRequestedReshadeVersion
    ) >/dev/null 2>&1
    _rc=$?
    set -e

    [[ $_rc -eq $EXIT_INTEGRITY ]]
    [[ ! -e $_calls ]]
}

run_cli_flag_tests() {
    echo -e "${BLUE}CLI Flag and Exit Status Tests${NC}"
    run_test "An unknown flag is a usage error" test_an_unknown_flag_is_a_usage_error
    run_test "Help leads with examples and the project page" test_help_leads_with_examples_and_names_the_project_page
    run_test "Conflicting flags are usage errors" test_conflicting_flags_are_usage_errors
    run_test "An invalid UI backend stops the run" test_an_invalid_ui_backend_stops_the_run
    run_test "A missing game path is a usage error" test_a_missing_game_path_is_a_usage_error
    run_test "--list-shader-repos --json is valid JSON with pins" test_list_shader_repos_json_is_valid_and_carries_pins
    run_test "JSON strings escape special characters" test_json_strings_escape_quotes_backslashes_and_control_characters
    run_test "--no-input without a game fails at once" test_no_input_without_a_game_fails_instead_of_waiting
    run_test "--no-input takes the detected DLL and stored packs" test_no_input_uses_the_detected_dll_and_stored_shader_selection
    run_test "--dry-run install changes nothing" test_dry_run_install_describes_the_plan_and_changes_nothing
    run_test "--dry-run creates no workspace" test_dry_run_does_not_create_a_missing_workspace
    run_test "--dry-run --uninstall keeps the links" test_dry_run_uninstall_lists_the_links_and_keeps_them
    run_test "--uninstall removes ReShade without asking" test_uninstall_flag_removes_reshade_without_asking
    run_test "--dry-run --update-all lists tracked games" test_dry_run_update_all_lists_every_tracked_game
    run_test "--quiet keeps results and errors only" test_quiet_drops_progress_output_but_keeps_results_and_errors
    run_test "A missing program exits 3" test_a_missing_program_exits_with_the_dependency_status
    run_test "An unreachable reshade.me exits 4" test_an_unreachable_reshade_site_exits_with_the_network_status
    run_test "latest falls back to the newest pinned build" test_latest_falls_back_to_the_newest_pinned_build
    run_test "An unpinned RESHADE_VERSION is refused first" test_an_unpinned_requested_version_is_refused_before_downloading
    echo ""
}
