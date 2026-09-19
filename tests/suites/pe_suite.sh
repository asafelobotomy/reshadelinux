#!/bin/bash

# Executable inspection: PE import analysis picks the architecture and DLL override.

_pe_field() {
    grep "^$2=" <<< "$1" | cut -d= -f2
}

_assert_pe_detection() {
    local _dir="$1" _arch="$2" _dll="$3" _result

    _result=$(detectExeInfo "$_dir")
    if [[ $(_pe_field "$_result" arch) != "$_arch" || $(_pe_field "$_result" dll) != "$_dll" ]]; then
        echo "expected arch=$_arch dll=$_dll but got: $(tr '\n' ' ' <<< "$_result")" >&2
        return 1
    fi
}

test_pe_detection_maps_direct3d11_to_dxgi_for_a_64_bit_game() {
    local _dir="$TEST_TEMP_DIR/pe-d3d11"

    mkdir -p "$_dir"
    create_mock_pe "$_dir/game.exe" 64 1024 KERNEL32.dll d3d11.dll
    _assert_pe_detection "$_dir" 64 dxgi
}

test_pe_detection_reads_a_32_bit_direct3d9_game() {
    local _dir="$TEST_TEMP_DIR/pe-d3d9"

    mkdir -p "$_dir"
    create_mock_pe "$_dir/game.exe" 32 1024 KERNEL32.dll d3d9.dll
    _assert_pe_detection "$_dir" 32 d3d9
}

test_pe_detection_prefers_the_newest_graphics_api() {
    local _dir="$TEST_TEMP_DIR/pe-priority"

    mkdir -p "$_dir"
    create_mock_pe "$_dir/game.exe" 64 1024 d3d11.dll d3d12.dll
    _assert_pe_detection "$_dir" 64 dxgi
}

test_pe_detection_recognises_opengl_and_legacy_apis() {
    local _dir="$TEST_TEMP_DIR/pe-opengl" _other="$TEST_TEMP_DIR/pe-ddraw"

    mkdir -p "$_dir" "$_other"
    create_mock_pe "$_dir/game.exe" 64 1024 KERNEL32.dll opengl32.dll
    create_mock_pe "$_other/game.exe" 32 1024 ddraw.dll
    _assert_pe_detection "$_dir" 64 opengl32
    _assert_pe_detection "$_other" 32 ddraw
}

test_pe_detection_ignores_helper_executables() {
    local _dir="$TEST_TEMP_DIR/pe-helpers"

    mkdir -p "$_dir"
    create_mock_pe "$_dir/UnityCrashHandler64.exe" 64 1024 d3d9.dll
    create_mock_pe "$_dir/game.exe" 64 1024 opengl32.dll
    _assert_pe_detection "$_dir" 64 opengl32
}

test_pe_detection_finds_imports_in_executables_larger_than_two_megabytes() {
    local _dir="$TEST_TEMP_DIR/pe-large"

    mkdir -p "$_dir"
    # The import table sits 3 MiB into the file, as it does in large game executables.
    create_mock_pe "$_dir/game.exe" 64 $((3 * 1024 * 1024)) KERNEL32.dll opengl32.dll
    _assert_pe_detection "$_dir" 64 opengl32
}

test_pe_detection_falls_back_by_architecture_when_no_graphics_api_is_imported() {
    local _dir="$TEST_TEMP_DIR/pe-none" _other="$TEST_TEMP_DIR/pe-none32"

    mkdir -p "$_dir" "$_other"
    create_mock_pe "$_dir/game.exe" 64 1024 KERNEL32.dll
    create_mock_pe "$_other/game.exe" 32 1024 KERNEL32.dll
    _assert_pe_detection "$_dir" 64 dxgi
    _assert_pe_detection "$_other" 32 d3d9
}

test_python_errors_are_written_to_the_debug_log() {
    local _err="$TEST_TEMP_DIR/python.err" _log="$TEST_TEMP_DIR/debug.log"

    printf 'Traceback (most recent call last):\nstruct.error: unpack_from requires a buffer\n' > "$_err"
    RESHADE_DEBUG_LOG="$_log" _logPythonErrors detectExeInfo "$_err"

    grep -q 'detectExeInfo: struct.error' "$_log"
    [[ ! -e $_err ]]
}

test_python_error_logging_is_silent_without_a_debug_log() {
    local _err="$TEST_TEMP_DIR/python.err" _output

    printf 'boom\n' > "$_err"
    _output=$( ( unset RESHADE_DEBUG_LOG; _logPythonErrors detectExeInfo "$_err" ) 2>&1 )

    [[ -z $_output ]]
    [[ ! -e $_err ]]
}

run_pe_tests() {
    echo -e "${BLUE}Executable Inspection Tests${NC}"
    run_test "PE maps Direct3D 11 to dxgi" test_pe_detection_maps_direct3d11_to_dxgi_for_a_64_bit_game
    run_test "PE reads a 32-bit Direct3D 9 game" test_pe_detection_reads_a_32_bit_direct3d9_game
    run_test "PE prefers the newest graphics API" test_pe_detection_prefers_the_newest_graphics_api
    run_test "PE recognises OpenGL and legacy APIs" test_pe_detection_recognises_opengl_and_legacy_apis
    run_test "PE ignores helper executables" test_pe_detection_ignores_helper_executables
    run_test "PE finds imports past two megabytes" test_pe_detection_finds_imports_in_executables_larger_than_two_megabytes
    run_test "PE falls back by architecture" test_pe_detection_falls_back_by_architecture_when_no_graphics_api_is_imported
    run_test "Python errors reach the debug log" test_python_errors_are_written_to_the_debug_log
    run_test "Python error logging is silent by default" test_python_error_logging_is_silent_without_a_debug_log
    echo ""
}
