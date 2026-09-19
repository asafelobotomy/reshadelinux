#!/bin/bash

# Download verification and installation into a game directory.

test_hash_pin_rejects_glob_patterns_instead_of_matching_them() {
    local _file="$TEST_TEMP_DIR/payload.bin" _pin _rc

    printf 'hello\n' > "$_file"
    for _pin in '*' '?' '[0-9a-f]*' '*abc' '[!x]*'; do
        set +e
        ( use_fatal_printErr; RESHADE_SETUP_SHA256="$_pin" verifyReshadeDownloadHash "$_file" ) >/dev/null 2>&1
        _rc=$?
        set -e
        if [[ $_rc -eq 0 ]]; then
            echo "pin '$_pin' was accepted for a file it cannot match" >&2
            return 1
        fi
    done
}

test_hash_pin_rejects_a_well_formed_hash_that_does_not_match() {
    local _file="$TEST_TEMP_DIR/payload.bin" _pin _rc

    printf 'hello\n' > "$_file"
    _pin=$(printf '0%.0s' {1..64})

    set +e
    ( use_fatal_printErr; RESHADE_SETUP_SHA256="$_pin" verifyReshadeDownloadHash "$_file" ) >/dev/null 2>&1
    _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
}

test_hash_pin_accepts_the_correct_hash_in_either_case() {
    local _file="$TEST_TEMP_DIR/payload.bin" _hash _rest

    printf 'hello\n' > "$_file"
    read -r _hash _rest < <(sha256sum "$_file")

    ( use_fatal_printErr; RESHADE_SETUP_SHA256="$_hash" verifyReshadeDownloadHash "$_file" ) >/dev/null 2>&1
    ( use_fatal_printErr; RESHADE_SETUP_SHA256="${_hash^^}" verifyReshadeDownloadHash "$_file" ) >/dev/null 2>&1
}

test_hash_pin_names_the_variable_when_the_value_is_malformed() {
    local _file="$TEST_TEMP_DIR/payload.bin" _output

    printf 'hello\n' > "$_file"
    _output=$( ( use_fatal_printErr; RESHADE_SETUP_SHA256='not-a-hash' verifyReshadeDownloadHash "$_file" ) 2>&1 || true )

    [[ $_output == *"RESHADE_SETUP_SHA256"* ]]
    [[ $_output == *"64"* ]]
}

test_hash_pin_is_skipped_when_unset() {
    local _file="$TEST_TEMP_DIR/payload.bin"

    printf 'hello\n' > "$_file"
    ( unset RESHADE_SETUP_SHA256; verifyReshadeDownloadHash "$_file" )
}

test_extra_dll_overrides_extend_the_known_list_and_ignore_invalid_entries() {
    export EXTRA_DLL_OVERRIDES="WinMM.dll, version bad-name ../evil"
    init_test_runtime_defaults 2>/dev/null

    isKnownDllOverride winmm
    isKnownDllOverride version
    isKnownDllOverride dxgi
    ! isKnownDllOverride bad-name
    ! isKnownDllOverride ../evil
    [[ " $COMMON_OVERRIDES " != *" bad-name "* ]]
}

test_manual_dll_entry_rejects_unknown_names_and_asks_again() {
    local _game="$TEST_TEMP_DIR/manual-dll-game" _out="$TEST_TEMP_DIR/manual-dll.out"

    mkdir -p "$_game"
    touch "$_game/game.exe"
    gamePath="$_game"
    _stateFile=""
    unset EXTRA_DLL_OVERRIDES
    init_test_runtime_defaults

    # n = decline the detected DLL, winmm = unknown, dxgi = known, y = confirm
    resolveInstallDllSelection < <(printf 'n\nwinmm\ndxgi\ny\n') > "$_out" 2>&1

    [[ $wantedDll == dxgi ]]
    grep -q "winmm" "$_out"
    grep -qi "not a supported" "$_out"
}

test_manual_dll_entry_accepts_names_added_through_extra_dll_overrides() {
    local _game="$TEST_TEMP_DIR/manual-dll-extra" _out="$TEST_TEMP_DIR/manual-dll-extra.out"

    mkdir -p "$_game"
    touch "$_game/game.exe"
    gamePath="$_game"
    _stateFile=""
    export EXTRA_DLL_OVERRIDES="winmm"
    init_test_runtime_defaults

    resolveInstallDllSelection < <(printf 'n\nwinmm\ny\n') > "$_out" 2>&1

    [[ $wantedDll == winmm ]]
}

test_batch_update_accepts_a_tracked_extra_dll_only_when_it_is_configured() {
    local _game="$TEST_TEMP_DIR/tracked-extra" _state="$TEST_TEMP_DIR/tracked-extra.state"

    mkdir -p "$_game"
    printf 'dll=winmm\narch=64\ngamePath=%s\nselected_repos=\napp_id=\n' "$_game" > "$_state"

    unset EXTRA_DLL_OVERRIDES
    init_test_runtime_defaults
    ! validateBatchUpdateState "$_state"

    export EXTRA_DLL_OVERRIDES="winmm"
    init_test_runtime_defaults
    validateBatchUpdateState "$_state"
}

test_manual_dll_entry_stops_when_input_closes_instead_of_looping() {
    local _game="$TEST_TEMP_DIR/manual-dll-eof" _pid _i _rc=0

    mkdir -p "$_game"
    touch "$_game/game.exe"
    gamePath="$_game"
    _stateFile=""
    unset EXTRA_DLL_OVERRIDES
    init_test_runtime_defaults

    # Decline the detected DLL, then close stdin during the manual prompt.
    # Production runs without errexit, so model that here; under `set -e` the old loop
    # would have ended by accident on read's EOF status.
    ( set +e; use_fatal_printErr; resolveInstallDllSelection < <(printf 'n\n') ) >/dev/null 2>&1 &
    _pid=$!

    for _i in {1..50}; do
        kill -0 "$_pid" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 "$_pid" 2>/dev/null; then
        kill "$_pid" 2>/dev/null
        wait "$_pid" 2>/dev/null || true
        echo "manual DLL prompt kept looping after stdin closed" >&2
        return 1
    fi

    wait "$_pid" || _rc=$?
    [[ $_rc -ne 0 ]]
}

run_install_tests() {
    echo -e "${BLUE}Install and Verification Tests${NC}"
    run_test "Hash pin rejects glob patterns" test_hash_pin_rejects_glob_patterns_instead_of_matching_them
    run_test "Hash pin rejects a non-matching hash" test_hash_pin_rejects_a_well_formed_hash_that_does_not_match
    run_test "Hash pin accepts the correct hash" test_hash_pin_accepts_the_correct_hash_in_either_case
    run_test "Hash pin names the variable when malformed" test_hash_pin_names_the_variable_when_the_value_is_malformed
    run_test "Hash pin is skipped when unset" test_hash_pin_is_skipped_when_unset
    run_test "EXTRA_DLL_OVERRIDES extends the list safely" test_extra_dll_overrides_extend_the_known_list_and_ignore_invalid_entries
    run_test "Manual DLL entry rejects unknown names" test_manual_dll_entry_rejects_unknown_names_and_asks_again
    run_test "Manual DLL entry accepts configured extras" test_manual_dll_entry_accepts_names_added_through_extra_dll_overrides
    run_test "Batch update accepts tracked extra DLLs" test_batch_update_accepts_a_tracked_extra_dll_only_when_it_is_configured
    run_test "Manual DLL prompt stops when input closes" test_manual_dll_entry_stops_when_input_closes_instead_of_looping
    echo ""
}
