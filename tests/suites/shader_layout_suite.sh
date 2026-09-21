#!/bin/bash
# shellcheck disable=SC2317,SC2329  # test functions and stubs are invoked indirectly
# shellcheck disable=SC2034  # variables are set for the code under test
# shellcheck disable=SC2154  # variables are assigned by the code under test

# How shader repositories lay out their content: directory-name case, and effects
# kept at the repository root instead of in Shaders/.

# Create a shader repo whose content directories use the given names, for example
# "shaders"/"textures" as CShade does. Files are <name>.fx, <name>.fxh and <name>.png.
_create_repo_with_dir_names() {
    local _name="$1" _shaders="$2" _textures="$3" _root="$MAIN_PATH/ReShade_shaders/$1"

    mkdir -p "$_root/$_shaders/shared" "$_root/$_textures"
    echo "// shader" > "$_root/$_shaders/$_name.fx"
    echo "// header" > "$_root/$_shaders/shared/$_name.fxh"
    echo "texture" > "$_root/$_textures/$_name.png"
}

test_shader_build_finds_lowercase_shader_and_texture_directories() {
    export SHADER_REPOS="https://example.com/a|lower-repo"
    _create_repo_with_dir_names lower-repo shaders textures

    buildGameShaderDir "81001" "lower-repo"

    [[ -L "$MAIN_PATH/game-shaders/81001/Merged/Shaders/lower-repo.fx" ]]
    [[ -L "$MAIN_PATH/game-shaders/81001/Merged/Shaders/shared/lower-repo.fxh" ]]
    [[ -L "$MAIN_PATH/game-shaders/81001/Merged/Textures/lower-repo.png" ]]
}

test_shader_build_finds_uppercase_and_mixed_case_directories() {
    export SHADER_REPOS="https://example.com/a|upper-repo;https://example.com/b|mixed-repo"
    _create_repo_with_dir_names upper-repo SHADERS TEXTURES
    _create_repo_with_dir_names mixed-repo sHaDeRs tExTuReS

    buildGameShaderDir "81002" "upper-repo,mixed-repo"

    [[ -L "$MAIN_PATH/game-shaders/81002/Merged/Shaders/upper-repo.fx" ]]
    [[ -L "$MAIN_PATH/game-shaders/81002/Merged/Textures/upper-repo.png" ]]
    [[ -L "$MAIN_PATH/game-shaders/81002/Merged/Shaders/mixed-repo.fx" ]]
    [[ -L "$MAIN_PATH/game-shaders/81002/Merged/Textures/mixed-repo.png" ]]
}

test_shader_build_links_headers_from_an_unselected_lowercase_repo() {
    export SHADER_REPOS="https://example.com/a|picked;https://example.com/b|lower-repo"
    create_mock_shader_repo "picked"
    _create_repo_with_dir_names lower-repo shaders textures
    echo "// shared include" > "$MAIN_PATH/ReShade_shaders/lower-repo/shaders/lower-include.fxh"

    buildGameShaderDir "81003" "picked"

    [[ ! -e "$MAIN_PATH/game-shaders/81003/Merged/Shaders/lower-repo.fx" ]]
    [[ -L "$MAIN_PATH/game-shaders/81003/Merged/Shaders/picked.fx" ]]
    [[ -L "$MAIN_PATH/game-shaders/81003/Merged/Shaders/lower-include.fxh" ]]
}

test_shader_build_prefers_the_exact_case_directory_when_both_exist() {
    export SHADER_REPOS="https://example.com/a|both-repo"
    create_mock_shader_repo "both-repo"
    mkdir -p "$MAIN_PATH/ReShade_shaders/both-repo/shaders"
    echo "// decoy" > "$MAIN_PATH/ReShade_shaders/both-repo/shaders/decoy.fx"

    buildGameShaderDir "81004" "both-repo"

    [[ -L "$MAIN_PATH/game-shaders/81004/Merged/Shaders/both-repo.fx" ]]
    [[ ! -e "$MAIN_PATH/game-shaders/81004/Merged/Shaders/decoy.fx" ]]
}

test_external_shaders_accept_lowercase_directories() {
    export SHADER_REPOS="https://example.com/a|some-repo"
    create_mock_shader_repo "some-repo"
    mkdir -p "$MAIN_PATH/External_shaders/shaders"
    echo "// mine" > "$MAIN_PATH/External_shaders/shaders/Mine.fx"

    buildGameShaderDir "81005" "some-repo"

    [[ -L "$MAIN_PATH/game-shaders/81005/Merged/Shaders/Mine.fx" ]]
}

# A repo such as ReshadeTFAA has no Shaders/ directory: its .fx sits at the top.
_create_root_level_repo() {
    local _root="$MAIN_PATH/ReShade_shaders/$1"

    mkdir -p "$_root/.git" "$_root/lib" "$_root/docs"
    echo "// effect" > "$_root/$1.fx"
    echo "// header" > "$_root/$1.fxh"
    echo "// nested header" > "$_root/lib/$1-nested.fxh"
    echo "not shader content" > "$_root/README.md"
    echo "image" > "$_root/docs/preview.png"
    echo "// git internals" > "$_root/.git/hook.fx"
}

test_shader_build_links_effects_kept_at_the_repository_root() {
    export SHADER_REPOS="https://example.com/a|root-repo"
    _create_root_level_repo root-repo

    buildGameShaderDir "82001" "root-repo"

    [[ -L "$MAIN_PATH/game-shaders/82001/Merged/Shaders/root-repo.fx" ]]
    [[ -L "$MAIN_PATH/game-shaders/82001/Merged/Shaders/root-repo.fxh" ]]
}

test_root_level_repo_keeps_the_relative_path_of_nested_headers() {
    export SHADER_REPOS="https://example.com/a|root-repo"
    _create_root_level_repo root-repo

    buildGameShaderDir "82002" "root-repo"

    [[ -L "$MAIN_PATH/game-shaders/82002/Merged/Shaders/lib/root-repo-nested.fxh" ]]
    [[ "$(readlink "$MAIN_PATH/game-shaders/82002/Merged/Shaders/lib/root-repo-nested.fxh")" == \
        "$(realpath "$MAIN_PATH/ReShade_shaders/root-repo/lib/root-repo-nested.fxh")" ]]
}

test_root_level_repo_never_links_git_internals_or_non_shader_files() {
    export SHADER_REPOS="https://example.com/a|root-repo"
    _create_root_level_repo root-repo

    buildGameShaderDir "82003" "root-repo"

    [[ ! -e "$MAIN_PATH/game-shaders/82003/Merged/Shaders/hook.fx" ]]
    [[ ! -e "$MAIN_PATH/game-shaders/82003/Merged/Shaders/.git" ]]
    [[ ! -e "$MAIN_PATH/game-shaders/82003/Merged/Shaders/README.md" ]]
    [[ ! -e "$MAIN_PATH/game-shaders/82003/Merged/Shaders/docs" ]]
}

test_root_level_repo_is_not_linked_when_unselected() {
    export SHADER_REPOS="https://example.com/a|picked;https://example.com/b|root-repo"
    create_mock_shader_repo "picked"
    _create_root_level_repo root-repo

    buildGameShaderDir "82004" "picked"

    [[ -L "$MAIN_PATH/game-shaders/82004/Merged/Shaders/picked.fx" ]]
    [[ ! -e "$MAIN_PATH/game-shaders/82004/Merged/Shaders/root-repo.fx" ]]
}

test_shaders_directory_wins_over_root_level_effects() {
    export SHADER_REPOS="https://example.com/a|mixed-repo"
    create_mock_shader_repo "mixed-repo"
    echo "// stray" > "$MAIN_PATH/ReShade_shaders/mixed-repo/Stray.fx"

    buildGameShaderDir "82005" "mixed-repo"

    [[ -L "$MAIN_PATH/game-shaders/82005/Merged/Shaders/mixed-repo.fx" ]]
    [[ ! -e "$MAIN_PATH/game-shaders/82005/Merged/Shaders/Stray.fx" ]]
}

test_root_level_repo_still_links_its_textures() {
    export SHADER_REPOS="https://example.com/a|root-repo"
    _create_root_level_repo root-repo
    mkdir -p "$MAIN_PATH/ReShade_shaders/root-repo/Textures"
    echo "texture" > "$MAIN_PATH/ReShade_shaders/root-repo/Textures/root-repo.png"

    buildGameShaderDir "82006" "root-repo"

    [[ -L "$MAIN_PATH/game-shaders/82006/Merged/Textures/root-repo.png" ]]
}

test_repo_has_root_level_effects_detects_only_top_level_fx() {
    _create_root_level_repo root-repo
    mkdir -p "$MAIN_PATH/ReShade_shaders/deep-repo/sub"
    echo "// deep" > "$MAIN_PATH/ReShade_shaders/deep-repo/sub/Deep.fx"

    _repoHasRootLevelEffects "$MAIN_PATH/ReShade_shaders/root-repo"
    assert_fails _repoHasRootLevelEffects "$MAIN_PATH/ReShade_shaders/deep-repo"
    assert_fails _repoHasRootLevelEffects "$MAIN_PATH/ReShade_shaders/missing-repo"
}

# Two packs that ship different copies of one header (BFBFX and ZenteonFX both have
# ZenteonCommon.fxh). The merge stays flat, because ReShade includes a header once per path:
# moving a pack into its own folder made headers reached from its nested folders load twice.
# The first copy therefore wins, and the build says so.
_create_pack_with_header() {
    local _name="$1" _header_body="$2" _root="$MAIN_PATH/ReShade_shaders/$1"

    mkdir -p "$_root/Shaders" "$_root/Textures"
    echo "// effect of $_name" > "$_root/Shaders/$_name.fx"
    echo "$_header_body" > "$_root/Shaders/Common.fxh"
    echo "texture" > "$_root/Textures/$_name.png"
}

test_conflicting_header_keeps_the_first_copy_and_warns_about_the_later_pack() {
    export SHADER_REPOS="https://example.com/a|first-pack;https://example.com/b|second-pack"
    _create_pack_with_header first-pack "// common v1"
    _create_pack_with_header second-pack "// common v2"

    local _output
    _output=$(buildGameShaderDir "83001" "first-pack,second-pack")

    local _shaders="$MAIN_PATH/game-shaders/83001/Merged/Shaders"
    grep -Fqx "// common v1" "$_shaders/Common.fxh"
    [[ -L "$_shaders/second-pack.fx" ]]
    [[ $_output == *"second-pack ships its own Common.fxh"* ]]
    [[ $_output != *"first-pack ships"* ]]
}

test_identical_headers_do_not_warn() {
    export SHADER_REPOS="https://example.com/a|first-pack;https://example.com/b|second-pack"
    _create_pack_with_header first-pack "// same"
    _create_pack_with_header second-pack "// same"

    local _output
    _output=$(buildGameShaderDir "83002" "first-pack,second-pack")

    [[ $_output != *"ships its own"* ]]
}

test_conflicting_effect_names_keep_the_first_and_only_log_the_second() {
    export SHADER_REPOS="https://example.com/a|first-pack;https://example.com/b|second-pack"
    _create_pack_with_header first-pack "// same"
    _create_pack_with_header second-pack "// same"
    echo "// NTSC A" > "$MAIN_PATH/ReShade_shaders/first-pack/Shaders/NTSC.fx"
    echo "// NTSC B" > "$MAIN_PATH/ReShade_shaders/second-pack/Shaders/NTSC.fx"
    export RESHADE_DEBUG_LOG="$TEST_TEMP_DIR/conflict-debug.log"

    local _output
    _output=$(buildGameShaderDir "83003" "first-pack,second-pack")

    grep -Fqx "// NTSC A" "$MAIN_PATH/game-shaders/83003/Merged/Shaders/NTSC.fx"
    [[ $_output != *"NTSC.fx"* ]]
    grep -Fq "Skipping second-pack/NTSC.fx" "$RESHADE_DEBUG_LOG"
}

test_a_pack_that_conflicts_with_nothing_stays_quiet() {
    export SHADER_REPOS="https://example.com/a|first-pack;https://example.com/b|second-pack"
    _create_pack_with_header first-pack "// common v1"
    mkdir -p "$MAIN_PATH/ReShade_shaders/second-pack/Shaders"
    echo "// only" > "$MAIN_PATH/ReShade_shaders/second-pack/Shaders/Unique.fx"

    local _output
    _output=$(buildGameShaderDir "83006" "first-pack,second-pack")

    [[ -L "$MAIN_PATH/game-shaders/83006/Merged/Shaders/Unique.fx" ]]
    [[ $_output != *"ships its own"* ]]
}

test_root_level_pack_with_a_conflicting_header_warns_too() {
    export SHADER_REPOS="https://example.com/a|first-pack;https://example.com/b|root-repo"
    _create_pack_with_header first-pack "// common v1"
    _create_root_level_repo root-repo
    echo "// common v2" > "$MAIN_PATH/ReShade_shaders/root-repo/Common.fxh"

    local _output
    _output=$(buildGameShaderDir "83007" "first-pack,root-repo")

    [[ $_output == *"root-repo ships its own Common.fxh"* ]]
    [[ -L "$MAIN_PATH/game-shaders/83007/Merged/Shaders/root-repo.fx" ]]
}

run_shader_layout_tests() {
    echo -e "${BLUE}Shader Repository Layout Tests${NC}"
    run_test "Build finds lowercase shader and texture dirs" test_shader_build_finds_lowercase_shader_and_texture_directories
    run_test "Build finds uppercase and mixed-case dirs" test_shader_build_finds_uppercase_and_mixed_case_directories
    run_test "Build links headers from an unselected lowercase repo" test_shader_build_links_headers_from_an_unselected_lowercase_repo
    run_test "Build prefers the exact-case dir when both exist" test_shader_build_prefers_the_exact_case_directory_when_both_exist
    run_test "External shaders accept lowercase dirs" test_external_shaders_accept_lowercase_directories
    run_test "Build links effects kept at the repo root" test_shader_build_links_effects_kept_at_the_repository_root
    run_test "Root-level repo keeps nested header paths" test_root_level_repo_keeps_the_relative_path_of_nested_headers
    run_test "Root-level repo skips git internals and non-shader files" test_root_level_repo_never_links_git_internals_or_non_shader_files
    run_test "Root-level repo is not linked when unselected" test_root_level_repo_is_not_linked_when_unselected
    run_test "Shaders dir wins over root-level effects" test_shaders_directory_wins_over_root_level_effects
    run_test "Root-level repo still links its textures" test_root_level_repo_still_links_its_textures
    run_test "Root-level detection only counts top-level fx" test_repo_has_root_level_effects_detects_only_top_level_fx
    run_test "Conflicting header keeps the first copy and warns" test_conflicting_header_keeps_the_first_copy_and_warns_about_the_later_pack
    run_test "Identical headers do not warn" test_identical_headers_do_not_warn
    run_test "Conflicting effect names are only logged" test_conflicting_effect_names_keep_the_first_and_only_log_the_second
    run_test "Pack without conflicts stays quiet" test_a_pack_that_conflicts_with_nothing_stays_quiet
    run_test "Root-level pack with a conflict warns" test_root_level_pack_with_a_conflicting_header_warns_too
    echo ""
}
