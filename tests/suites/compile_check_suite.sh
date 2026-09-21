#!/bin/bash
# shellcheck disable=SC2030,SC2031  # the script is sourced inside subshells on purpose
# shellcheck disable=SC2317,SC2329  # test functions and stubs are invoked indirectly
# shellcheck disable=SC1090  # the script under test is sourced through a variable
# shellcheck disable=SC2034  # settings are assigned for the sourced script to read

# The opt-in Proton compile check (scripts/diagnostics/compile_check.sh). Nothing here starts
# Proton or touches the network: the report parser reads fixture logs and the download
# helper reads a local archive.

_CC_SCRIPT="$REPO_DIR/scripts/diagnostics/compile_check.sh"

test_compile_check_help_and_bad_options_are_reported_without_side_effects() {
    local _output _status=0

    _output=$(bash "$_CC_SCRIPT" --help)
    [[ $_output == *"--packs LIST"* ]]

    _output=$(bash "$_CC_SCRIPT" --bogus 2>&1) || _status=$?
    [[ $_status -eq 2 ]]
    [[ $_output == *"unknown option: --bogus"* ]]

    _status=0
    _output=$(bash "$_CC_SCRIPT" --timeout soon 2>&1) || _status=$?
    [[ $_status -eq 2 ]]
    [[ $_output == *"take a number of seconds"* ]]

    _status=0
    _output=$(bash "$_CC_SCRIPT" --packs 2>&1) || _status=$?
    [[ $_status -eq 2 ]]
    [[ $_output == *"--packs needs a value"* ]]
}

test_compile_check_rejects_an_unknown_pack_before_downloading_anything() {
    local _lab="$TEST_TEMP_DIR/lab" _output _status=0

    _output=$(DISPLAY=:99 bash "$_CC_SCRIPT" --lab "$_lab" --packs no-such-pack 2>&1) || _status=$?

    [[ $_status -eq 2 ]]
    [[ $_output == *"unknown shader repository: no-such-pack"* ]]
    [[ ! -e $_lab/proton && ! -e $_lab/downloads ]]
}

test_compile_check_needs_a_display_or_xvfb() {
    local _stub="$TEST_TEMP_DIR/bin" _tool _output _status=0

    mkdir -p "$_stub"
    for _tool in curl tar git python3 sha256sum find setsid uname; do
        ln -s "$(command -v "$_tool")" "$_stub/$_tool"
    done

    _output=$(
        source "$_CC_SCRIPT"
        unset DISPLAY WAYLAND_DISPLAY
        PATH="$_stub"
        check_prerequisites 2>&1
    ) || _status=$?

    [[ $_status -eq 2 ]]
    [[ $_output == *"no display found"* ]]
}

test_compile_check_names_the_missing_tools() {
    local _stub="$TEST_TEMP_DIR/bin-empty" _output _status=0

    mkdir -p "$_stub"
    _output=$(
        source "$_CC_SCRIPT"
        PATH="$_stub"
        check_prerequisites 2>&1
    ) || _status=$?

    [[ $_status -eq 2 ]]
    [[ $_output == *"missing required tools: curl tar git python3 sha256sum find setsid uname"* ]]
}

test_purge_removes_only_a_directory_the_script_created() {
    local _mine="$TEST_TEMP_DIR/my-lab" _foreign="$TEST_TEMP_DIR/foreign" _output _status=0

    mkdir -p "$_mine" "$_foreign"
    touch "$_mine/.reshadelinux-compile-check" "$_foreign/precious.txt"

    bash "$_CC_SCRIPT" --lab "$_mine" --purge >/dev/null
    [[ ! -e $_mine ]]

    _output=$(bash "$_CC_SCRIPT" --lab "$_foreign" --purge 2>&1) || _status=$?
    [[ $_status -eq 2 ]]
    [[ -f $_foreign/precious.txt ]]
    [[ $_output == *"refusing to delete"* ]]
}

test_compile_check_refuses_a_lab_directory_that_already_holds_other_files() {
    local _dir="$TEST_TEMP_DIR/documents" _output _status=0

    mkdir -p "$_dir"
    touch "$_dir/thesis.txt"

    _output=$(DISPLAY=:99 bash "$_CC_SCRIPT" --lab "$_dir" --packs no-such-pack 2>&1) || _status=$?

    [[ $_status -eq 2 ]]
    [[ $_output == *"not empty"* ]]
    [[ ! -e $_dir/.reshadelinux-compile-check ]]
    # and a later --purge cannot be talked into deleting it
    assert_fails bash "$_CC_SCRIPT" --lab "$_dir" --purge
    [[ -f $_dir/thesis.txt ]]
}

test_compile_check_accepts_an_empty_or_new_lab_directory() {
    local _output _status=0

    mkdir -p "$TEST_TEMP_DIR/empty-lab"
    _output=$(DISPLAY=:99 bash "$_CC_SCRIPT" --lab "$TEST_TEMP_DIR/empty-lab" --packs no-such-pack 2>&1) || _status=$?

    [[ $_output == *"unknown shader repository"* ]]
    [[ -f $TEST_TEMP_DIR/empty-lab/.reshadelinux-compile-check ]]
}

test_a_relative_lab_directory_becomes_absolute_before_anything_changes_directory() {
    (
        source "$_CC_SCRIPT"
        cd "$TEST_TEMP_DIR" || exit 1
        parse_args --lab relative-lab
        [[ $LAB == "$TEST_TEMP_DIR/relative-lab" ]]
    )
}

test_compile_check_stops_early_when_no_effect_was_merged() {
    local _output _status=0

    _output=$(
        source "$_CC_SCRIPT"
        LAB="$TEST_TEMP_DIR/empty-build-lab"
        mkdir -p "$LAB/logs" "$LAB/data" "$LAB/reshade/6.0.0"
        touch "$LAB/d3dtest.exe" "$LAB/reshade/6.0.0/ReShade64.dll" "$LAB/data/d3dcompiler_47.dll.64"
        MAIN_PATH="$LAB/data"
        RESHADE_CHECKED_VERSION=6.0.0
        SHADER_BROKEN_EFFECTS=""
        ensureSelectedShaderRepos() { return 0; }
        downloadD3dcompiler_47() { return 0; }
        buildGameShaderDir() { mkdir -p "$MAIN_PATH/game-shaders/compile-check/Merged/Shaders"; }
        ensureGameIni() { return 0; }
        prepare_game "nothing" 2>&1
    ) || _status=$?

    [[ $_status -eq 2 ]]
    [[ $_output == *"no effect was merged"* ]]
}

test_compile_check_refuses_a_machine_it_has_no_toolchain_for() {
    local _stub="$TEST_TEMP_DIR/arch-bin" _tool _output _status=0

    mkdir -p "$_stub"
    for _tool in curl tar git python3 sha256sum find setsid; do
        ln -sf "$(command -v "$_tool")" "$_stub/$_tool"
    done
    printf '#!/bin/sh\necho aarch64\n' > "$_stub/uname"
    chmod +x "$_stub/uname"

    _output=$(
        source "$_CC_SCRIPT"
        PATH="$_stub"
        DISPLAY=:0
        check_prerequisites 2>&1
    ) || _status=$?

    [[ $_status -eq 2 ]]
    [[ $_output == *"x86_64"* ]]
}

# A small archive with one top-level folder, as the real tool downloads have.
_cc_make_archive() {
    local _archive="$TEST_TEMP_DIR/tool.tar.gz"

    mkdir -p "$TEST_TEMP_DIR/tool-src/tool-1.0/bin"
    echo "tool" > "$TEST_TEMP_DIR/tool-src/tool-1.0/bin/run"
    tar -czf "$_archive" -C "$TEST_TEMP_DIR/tool-src" tool-1.0
    printf '%s\n' "$_archive"
}

test_fetch_tool_unpacks_an_archive_whose_checksum_matches() {
    local _archive _sum _rest

    _archive=$(_cc_make_archive)
    read -r _sum _rest < <(sha256sum "$_archive")

    (
        source "$_CC_SCRIPT"
        LAB="$TEST_TEMP_DIR/fetch-lab"
        fetch_tool "file://$_archive" "$_sum" "$LAB/tool" >/dev/null
        [[ -f $LAB/tool/bin/run && -f $LAB/tool/.complete ]]
        # A second call does not need the download again.
        rm -f "$_archive"
        fetch_tool "file://$_archive" "$_sum" "$LAB/tool" >/dev/null
    )
}

test_fetch_tool_unpacks_nothing_when_the_checksum_differs() {
    local _archive _output _status=0

    _archive=$(_cc_make_archive)

    _output=$(
        source "$_CC_SCRIPT"
        LAB="$TEST_TEMP_DIR/fetch-lab-bad"
        fetch_tool "file://$_archive" "0000000000000000000000000000000000000000000000000000000000000000" "$LAB/tool" 2>&1
    ) || _status=$?

    [[ $_status -eq 2 ]]
    [[ $_output == *"checksum mismatch"* ]]
    [[ ! -e $TEST_TEMP_DIR/fetch-lab-bad/tool ]]
}

test_pinned_tool_checksums_are_well_formed() {
    (
        source "$_CC_SCRIPT"
        [[ $GE_PROTON_SHA256 =~ ^[0-9a-f]{64}$ ]]
        [[ $LLVM_MINGW_SHA256 =~ ^[0-9a-f]{64}$ ]]
        [[ -n $GE_PROTON_TAG && -n $LLVM_MINGW_TAG ]]
    )
}

test_compile_progress_counts_reported_effects() {
    local _log="$TEST_TEMP_DIR/ReShade.log"

    (
        source "$_CC_SCRIPT"
        [[ $(compile_progress "$TEST_TEMP_DIR/missing.log") == 0 ]]
        : > "$_log"
        [[ $(compile_progress "$_log") == 0 ]]
        _cc_write_log "$_log"
        [[ $(compile_progress "$_log") == 4 ]]
    )
}

test_wait_for_compile_returns_at_once_when_every_effect_is_reported() {
    local _log="$TEST_TEMP_DIR/ReShade.log"

    _cc_write_log "$_log"
    (
        source "$_CC_SCRIPT"
        POLL_SECONDS=1
        wait_for_compile "$_log" 4 "$$"
    )
}

test_wait_for_compile_gives_up_when_no_effect_is_reported_for_the_stall_time() {
    local _log="$TEST_TEMP_DIR/ReShade.log" _status=0

    _cc_write_log "$_log"
    sleep 30 &
    local _pid=$!
    (
        source "$_CC_SCRIPT"
        POLL_SECONDS=1 STALL_SECONDS=2 TIMEOUT_SECONDS=20
        wait_for_compile "$_log" 99 "$_pid"
    ) || _status=$?
    kill "$_pid"
    wait "$_pid" || true

    [[ $_status -eq 3 ]]
}

test_wait_for_compile_notices_a_program_that_ended_early() {
    local _log="$TEST_TEMP_DIR/ReShade.log" _status=0 _output

    _cc_write_log "$_log"
    sleep 0 &
    local _pid=$!
    wait "$_pid"
    _output=$(
        source "$_CC_SCRIPT"
        POLL_SECONDS=1 STALL_SECONDS=30 TIMEOUT_SECONDS=30
        wait_for_compile "$_log" 99 "$_pid" 2>&1
    ) || _status=$?

    [[ $_status -eq 4 ]]
    [[ -z $_output ]]
}

run_compile_check_tests() {
    echo -e "${BLUE}Compile Check Tests${NC}"
    run_test "Compile check help and bad options" test_compile_check_help_and_bad_options_are_reported_without_side_effects
    run_test "Compile check rejects an unknown pack early" test_compile_check_rejects_an_unknown_pack_before_downloading_anything
    run_test "Compile check needs a display or xvfb" test_compile_check_needs_a_display_or_xvfb
    run_test "Compile check names missing tools" test_compile_check_names_the_missing_tools
    run_test "Purge only removes its own directory" test_purge_removes_only_a_directory_the_script_created
    run_test "Fetch unpacks a matching archive" test_fetch_tool_unpacks_an_archive_whose_checksum_matches
    run_test "Fetch unpacks nothing on a checksum mismatch" test_fetch_tool_unpacks_nothing_when_the_checksum_differs
    run_test "Pinned checksums are well formed" test_pinned_tool_checksums_are_well_formed
    run_test "Progress counts reported effects" test_compile_progress_counts_reported_effects
    run_test "Wait returns when everything is reported" test_wait_for_compile_returns_at_once_when_every_effect_is_reported
    run_test "Wait gives up after the stall time" test_wait_for_compile_gives_up_when_no_effect_is_reported_for_the_stall_time
    run_test "Wait notices an early exit" test_wait_for_compile_notices_a_program_that_ended_early
    run_test "Compile check refuses a non-empty foreign lab directory" test_compile_check_refuses_a_lab_directory_that_already_holds_other_files
    run_test "Compile check accepts an empty or new lab directory" test_compile_check_accepts_an_empty_or_new_lab_directory
    run_test "A relative lab directory becomes absolute" test_a_relative_lab_directory_becomes_absolute_before_anything_changes_directory
    run_test "Compile check stops when no effect was merged" test_compile_check_stops_early_when_no_effect_was_merged
    run_test "Compile check refuses a non-x86_64 machine" test_compile_check_refuses_a_machine_it_has_no_toolchain_for
    echo ""
}
