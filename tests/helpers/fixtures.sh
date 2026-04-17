#!/bin/bash
# Test fixtures and helper functions for reshadelinux.sh tests
# Sets up mock Steam structures and game directories for testing

set -euo pipefail

# Create temporary test environment
setup_test_env() {
    TEST_REAL_HOME="${HOME:-}"
    export TEST_REAL_HOME
    TEST_TEMP_DIR=$(mktemp -d)
    export TEST_TEMP_DIR
    export HOME="$TEST_TEMP_DIR/home"
    mkdir -p "$HOME"
    
    # Isolate the icon cache so tests don't read/write the real user cache.
    export XDG_CACHE_HOME="$TEST_TEMP_DIR/.cache"
    
    # Create fake Steam directory structure
    TEST_STEAM_ROOT="$TEST_TEMP_DIR/Steam"
    TEST_STEAM_CACHE="$TEST_STEAM_ROOT/appcache/librarycache"
    TEST_GAMES_DIR="$TEST_TEMP_DIR/steamapps/common"
    
    mkdir -p "$TEST_STEAM_CACHE"
    mkdir -p "$TEST_GAMES_DIR"
    
    # Create cache directory for reshade icons (within test dir)
    TEST_ICON_CACHE="$XDG_CACHE_HOME/reshadelinux/icons"
    mkdir -p "$TEST_ICON_CACHE"
    
    # Set MAIN_PATH to an isolated temp location for state/shader tests
    export MAIN_PATH="$TEST_TEMP_DIR/reshade"
    export RESHADE_PATH="$MAIN_PATH/reshade"
    mkdir -p "$MAIN_PATH/ReShade_shaders" "$MAIN_PATH/External_shaders" \
             "$MAIN_PATH/game-state" "$MAIN_PATH/game-shaders" "$RESHADE_PATH"
}

# Clean up test environment
teardown_test_env() {
    if [[ -n "${TEST_REAL_HOME:-}" ]]; then
        export HOME="$TEST_REAL_HOME"
    fi
    [[ -n "${TEST_TEMP_DIR:-}" ]] && rm -rf "$TEST_TEMP_DIR"
}

# Create a mock game with specified exes
create_mock_game() {
    local game_name="$1"
    local appid="$2"
    shift 2
    local exes=("$@")
    
    local game_dir="$TEST_GAMES_DIR/$game_name"
    mkdir -p "$game_dir"
    
    # Create exe files
    for exe in "${exes[@]}"; do
        touch "$game_dir/$exe"
    done
    
    # Create mock game manifest (ACF file)
    local manifest="$TEST_TEMP_DIR/steamapps/appmanifest_${appid}.acf"
    cat > "$manifest" << EOF
"AppState"
{
	"appid"	"${appid}"
	"Universe"	"1"
	"name"	"$game_name"
	"StateFlags"	"4"
	"LastUpdated"	"1234567890"
	"UpdateResult"	"0"
	"SizeOnDisk"	"0"
	"buildid"	"0000000"
	"LastDecoded"	"0"
	"UpdateFlags"	"0"
	"MountedConfig"	"/config"
	"ContentType"	"1"
	"SurfaceFormat"	"2"
	"Language"	"english"
	"Type"	"1"
	"BaseInstallFolder"	"${TEST_TEMP_DIR}"
	"SymlinkSource"	""
	"LastUpdateCheck"	"0000000000"
	"ScheduledAutoUpdate"	"0"
	"AutoUpdateBehavior"	"0"
	"AllowOtherDownloadsWhilePaused"	"0"
	"AllowRunInBackground"	"1"
	"FullValidateOnNextUpdate"	"0"
	"AllowDownloadsWhilePaused"	"1"
	"IsAvailableOnFreeTier"	"1"
	"IsFreeAppLicense"	"0"
	"InstallDir"	"$game_name"
	"VersionSetID"	"0"
	"VersionNumber"	"0"
	"GameKey"	"0"
	"Flags"	"0"
	"Options"	""
}
EOF
}

# Create a mock icon file
create_mock_icon() {
    local appid="$1"
    local icon_path="$TEST_STEAM_CACHE/${appid}"
    mkdir -p "$icon_path"
    
    # Create a tiny valid PNG (1x1 transparent)
    printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82' > "$icon_path/logo.png"
    
    # Also create a hash-named jpg (actual game icon)
    echo "fake mini icon" > "$icon_path/6cf7b10dd29db28448ef79698ed2118a03617d63.jpg"
    
    # Create header.jpg (banner fallback)
    echo "fake banner" > "$icon_path/header.jpg"
    
    # Create library files (should be skipped)
    echo "library content" > "$icon_path/library_600x900.jpg"
}

# Create test game: Warhammer 40K with multiple exes
create_warhammer_test() {
    create_mock_game "Warhammer 40,000 Rogue Trader" "2021390" \
        "WH40KRT.exe" \
        "UnityCrashHandler64.exe"
}

# Create test game: Cities Skylines with single exe
create_cities_skylines_test() {
    create_mock_game "Cities_Skylines" "255710" \
        "Cities.exe"
    create_mock_icon "255710"
}

# Create test game: with utility exes to filter
create_complex_exes_test() {
    create_mock_game "Complex Game" "999999" \
        "game.exe" \
        "game_launcher.exe" \
        "UnityPlayer.exe" \
        "EasyAntiCheat.exe" \
        "setup.exe"
}

# Create a fake shader repository with some .fx / .fxh files.
# $1: repo local name (e.g. "sweetfx-shaders")
# Places files under $MAIN_PATH/ReShade_shaders/$1/Shaders/ and .../Textures/
create_mock_shader_repo() {
    local _name="$1"
    local _shaders="$MAIN_PATH/ReShade_shaders/$_name/Shaders"
    local _textures="$MAIN_PATH/ReShade_shaders/$_name/Textures"
    mkdir -p "$_shaders" "$_textures"
    echo "// shader" > "$_shaders/$_name.fx"
    echo "// header" > "$_shaders/$_name.fxh"
    echo "texture"   > "$_textures/$_name.png"
}

# Create a fake shader repository where Shaders and Textures live below a nested directory.
# $1: repo local name
create_nested_shader_repo() {
    local _name="$1"
    local _base="$MAIN_PATH/ReShade_shaders/$_name/release/package"
    local _shaders="$_base/Shaders/Lighting"
    local _textures="$_base/Textures/Noise"
    mkdir -p "$_shaders" "$_textures"
    echo "// shader" > "$_base/Shaders/$_name.fx"
    echo "// nested header" > "$_shaders/$_name.fxh"
    echo "texture" > "$_textures/$_name.png"
}

# Source the main script functions (for testing)
# This function extracts and loads only the functions we need to test
load_functions_from_script() {
    local script_path="${1:-.}"
    local script_file
    
    # Find the reshadelinux.sh script
    if [[ ! -f "$script_path/reshadelinux.sh" ]]; then
        script_path="$(dirname "${BASH_SOURCE[0]}")/.."
    fi
    script_file="$script_path/reshadelinux.sh"
    
    if [[ -f "$script_file" ]]; then
        # Source the script but suppress version check and update messages
        # shellcheck disable=SC1090
        SKIP_RESHADE_CHECK=1 source "$script_file" 2>/dev/null || true
    fi
}

# Helper: assert file exists
assert_file_exists() {
    local file="$1"
    [[ -f "$file" ]] || (echo "ERROR: File does not exist: $file" && return 1)
    return 0
}

# Helper: assert directory exists
assert_dir_exists() {
    local dir="$1"
    [[ -d "$dir" ]] || (echo "ERROR: Directory does not exist: $dir" && return 1)
    return 0
}

# Helper: assert string matches pattern
assert_matches() {
    local string="$1"
    local pattern="$2"
    [[ "$string" =~ $pattern ]] || (echo "ERROR: '$string' does not match pattern '$pattern'" && return 1)
    return 0
}

# Helper: assert executable detection
assert_exe_selected() {
    local dir="$1"
    local expected="$2"
    local result
    result=$(pickBestExeInDir "$dir" 2>/dev/null || echo "")
    [[ "$result" == "$expected" ]] || (echo "ERROR: Expected '$expected' but got '$result'" && return 1)
    return 0
}

# Helper: assert icon path detection
assert_icon_found() {
    local appid="$1"
    local result
    result=$(findSteamIconPath "$TEST_STEAM_ROOT" "$appid" 2>/dev/null || echo "")
    [[ -n "$result" ]] || (echo "ERROR: No icon found for AppID $appid" && return 1)
    return 0
}

# Helper: assert preset lookup
assert_preset_value() {
    local appid="$1"
    local expected="$2"
    local result
    result=$(getBuiltInGameDirPreset "$appid" 2>/dev/null || echo "")
    [[ "$result" == "$expected" ]] || (echo "ERROR: Expected preset '$expected' but got '$result'" && return 1)
    return 0
}
