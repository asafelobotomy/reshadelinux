#!/bin/bash

# Per-game shader directory construction, selection and ini generation.

test_shader_build_supports_description_without_branch() {
    export SHADER_REPOS="https://example.com/a|alpha||Alpha description"
    create_mock_shader_repo "alpha"
    buildGameShaderDir "55555" "alpha"
    [[ -L "$MAIN_PATH/game-shaders/55555/Merged/Shaders/alpha.fx" ]]
}

test_shader_build_mirrors_root_headers_above_shaders() {
    export SHADER_REPOS="https://example.com/a|alpha"
    create_mock_shader_repo "alpha"
    buildGameShaderDir "57575" "alpha"
    [[ -L "$MAIN_PATH/game-shaders/57575/Merged/Shaders/alpha.fxh" ]]
    [[ -L "$MAIN_PATH/game-shaders/57575/Merged/alpha.fxh" ]]
}

test_shader_build_exposes_nested_headers_at_shader_root() {
    export SHADER_REPOS="https://example.com/a|nested-repo"
    create_nested_shader_repo "nested-repo"
    buildGameShaderDir "58585" "nested-repo"
    [[ -L "$MAIN_PATH/game-shaders/58585/Merged/Shaders/nested-repo.fxh" ]]
}

test_shader_build_removes_app_specific_excluded_effects() {
    export SHADER_REPOS="https://example.com/a|alpha"
    export SHADER_EFFECT_EXCLUDES="424242|Bad.fx"
    create_mock_shader_repo "alpha"
    mv "$MAIN_PATH/ReShade_shaders/alpha/Shaders/alpha.fx" "$MAIN_PATH/ReShade_shaders/alpha/Shaders/Bad.fx"

    buildGameShaderDir "59595" "alpha" "424242"

    [[ ! -e "$MAIN_PATH/game-shaders/59595/Merged/Shaders/Bad.fx" ]]
    [[ -L "$MAIN_PATH/game-shaders/59595/Merged/Shaders/alpha.fxh" ]]
}

test_shader_build_keeps_effects_for_other_apps() {
    export SHADER_REPOS="https://example.com/a|alpha"
    export SHADER_EFFECT_EXCLUDES="424242|Bad.fx"
    create_mock_shader_repo "alpha"
    mv "$MAIN_PATH/ReShade_shaders/alpha/Shaders/alpha.fx" "$MAIN_PATH/ReShade_shaders/alpha/Shaders/Bad.fx"

    buildGameShaderDir "60606" "alpha" "111111"

    [[ -L "$MAIN_PATH/game-shaders/60606/Merged/Shaders/Bad.fx" ]]
}

test_shader_build_discovers_nested_layouts() {
    export SHADER_REPOS="https://example.com/a|nested-repo"
    create_nested_shader_repo "nested-repo"
    buildGameShaderDir "56565" "nested-repo"
    [[ -L "$MAIN_PATH/game-shaders/56565/Merged/Shaders/nested-repo.fx" ]]
    [[ -L "$MAIN_PATH/game-shaders/56565/Merged/Shaders/Lighting/nested-repo.fxh" ]]
    [[ -L "$MAIN_PATH/game-shaders/56565/Merged/Textures/Noise/nested-repo.png" ]]
}

test_shader_available_selected_repos_only_returns_existing_dirs() {
    export SHADER_REPOS="https://example.com/a|alpha;https://example.com/b|beta"
    create_mock_shader_repo "alpha"
    [[ "$(getAvailableSelectedRepos "alpha,beta")" == "alpha" ]]
}

test_shader_cli_selection_returns_names_only() {
    local _output
    export SHADER_REPOS="https://example.com/a|alpha||Alpha repo"
    _UI_BACKEND=cli
    _output=$(printf '\n' | selectShaders "alpha" 2>/dev/null)
    [[ "$_output" == "alpha" ]]
}

test_shader_auto_confirm_keeps_current_selection() {
    local _output
    export SHADER_REPOS="https://example.com/a|alpha||Alpha repo;https://example.com/b|beta||Beta repo"
    _output=$( (
        _UI_BACKEND=dialog
        UI_AUTO_CONFIRM=1
        selectShaders "alpha,beta"
    ) )

    [[ "$_output" == "alpha,beta" ]]
}

test_shader_auto_confirm_defaults_to_all_repos_when_selection_is_empty() {
    local _output
    export SHADER_REPOS="https://example.com/a|alpha||Alpha repo;https://example.com/b|beta||Beta repo"
    _output=$( (
        _UI_BACKEND=dialog
        UI_AUTO_CONFIRM=1
        selectShaders ""
    ) )

    [[ "$_output" == "alpha,beta" ]]
}

test_install_first_run_defaults_to_curated_subset() {
    local _game_dir="$TEST_TEMP_DIR/first-run-game"
    local _output
    mkdir -p "$_game_dir"
    export SHADER_REPOS="https://example.com/a|alpha||Alpha repo;https://example.com/b|beta||Beta repo;https://example.com/c|gamma||Gamma repo"
    export FIRST_RUN_SHADER_REPOS="gamma,alpha"

    _output=$( (
        _stateFile="$MAIN_PATH/game-state/non-existent.state"

        selectShaders() {
            printf '%s\n' "$1"
        }

        ensureSelectedShaderReposWithRetry() {
            return 0
        }

        getAvailableSelectedRepos() {
            printf '%s\n' "$1"
        }

        resolveInstallShaderSelection >/dev/null
        printf '%s\n' "$_selectedRepos"
    ) )

    [[ "$_output" == "alpha,gamma" ]]
}

test_shader_yad_selection_accepts_multiline_output() {
    local _output

    export SHADER_REPOS="https://example.com/a|alpha;https://example.com/b|beta;https://example.com/c|gamma"
    _output=$( (
        _UI_BACKEND=yad
        # shellcheck disable=SC2329
        ui_checklist() {
            printf '1\n2\n3\n'
        }
        selectShaders "alpha"
    ) )

    [[ "$_output" == "alpha,beta,gamma" ]]
}

test_shader_build_creates_dir() {
    export SHADER_REPOS="https://example.com/repo|test-shaders"
    create_mock_shader_repo "test-shaders"
    buildGameShaderDir "99999" "test-shaders"
    [[ -d "$MAIN_PATH/game-shaders/99999/Merged/Shaders" ]]
}

test_shader_build_links_selected_repo() {
    export SHADER_REPOS="https://example.com/a|alpha-shaders;https://example.com/b|beta-shaders"
    create_mock_shader_repo "alpha-shaders"
    create_mock_shader_repo "beta-shaders"
    buildGameShaderDir "11111" "alpha-shaders"
    [[ -L "$MAIN_PATH/game-shaders/11111/Merged/Shaders/alpha-shaders.fx" ]] || return 1
    [[ ! -e "$MAIN_PATH/game-shaders/11111/Merged/Shaders/beta-shaders.fx" ]]
}

test_shader_build_excludes_unselected_repo() {
    export SHADER_REPOS="https://example.com/a|alpha-shaders;https://example.com/b|beta-shaders"
    create_mock_shader_repo "alpha-shaders"
    create_mock_shader_repo "beta-shaders"
    buildGameShaderDir "22222" "beta-shaders"
    [[ -L "$MAIN_PATH/game-shaders/22222/Merged/Shaders/beta-shaders.fx" ]] || return 1
    [[ ! -e "$MAIN_PATH/game-shaders/22222/Merged/Shaders/alpha-shaders.fx" ]]
}

test_shader_build_includes_fxh_from_unselected_repo() {
    export SHADER_REPOS="https://example.com/a|alpha-shaders;https://example.com/b|beta-shaders"
    create_mock_shader_repo "alpha-shaders"
    create_mock_shader_repo "beta-shaders"
    # Only select alpha — beta's .fx must be absent but its .fxh must be present
    buildGameShaderDir "55555" "alpha-shaders"
    [[ -L "$MAIN_PATH/game-shaders/55555/Merged/Shaders/alpha-shaders.fx" ]] || return 1
    [[ ! -e "$MAIN_PATH/game-shaders/55555/Merged/Shaders/beta-shaders.fx" ]] || return 1
    [[ -L "$MAIN_PATH/game-shaders/55555/Merged/Shaders/beta-shaders.fxh" ]]
}

test_shader_build_includes_external() {
    export SHADER_REPOS="https://example.com/r|some-repo"
    create_mock_shader_repo "some-repo"
    echo "// external" > "$MAIN_PATH/External_shaders/MyCustom.fx"
    buildGameShaderDir "33333" "some-repo"
    [[ -L "$MAIN_PATH/game-shaders/33333/Merged/Shaders/MyCustom.fx" ]]
}

test_shader_rebuild_replaces_previous() {
    export SHADER_REPOS="https://example.com/a|alpha-shaders;https://example.com/b|beta-shaders"
    create_mock_shader_repo "alpha-shaders"
    create_mock_shader_repo "beta-shaders"
    buildGameShaderDir "44444" "alpha-shaders"
    [[ -L "$MAIN_PATH/game-shaders/44444/Merged/Shaders/alpha-shaders.fx" ]] || return 1
    buildGameShaderDir "44444" "beta-shaders"
    [[ -L "$MAIN_PATH/game-shaders/44444/Merged/Shaders/beta-shaders.fx" ]] || return 1
    [[ ! -e "$MAIN_PATH/game-shaders/44444/Merged/Shaders/alpha-shaders.fx" ]]
}

test_game_ini_is_per_game_and_relative() {
    local _game_dir="$TEST_TEMP_DIR/nonsteam-game"
    mkdir -p "$_game_dir"
    ensureGameIni "$_game_dir"
    grep -Fqx 'EffectSearchPaths=.\ReShade_shaders\Merged\Shaders' "$_game_dir/ReShade.ini"
    grep -Fqx 'TextureSearchPaths=.\ReShade_shaders\Merged\Textures' "$_game_dir/ReShade.ini"
}

test_shader_header_helpers_exist_before_any_merge_runs() {
    declare -F exposeNestedShaderHeadersToRoot >/dev/null
    declare -F mirrorShaderHeadersToMergedRoot >/dev/null
}

test_shader_build_with_no_repos_and_no_external_shaders_is_quiet() {
    local _stderr

    export SHADER_REPOS="https://example.com/repo|test-shaders"
    rm -rf "$MAIN_PATH/External_shaders"
    _stderr=$(buildGameShaderDir "77777" "" "" 2>&1 >/dev/null)

    [[ -z $_stderr ]]
    [[ -d "$MAIN_PATH/game-shaders/77777/Merged/Shaders" ]]
}

test_helper_functions_do_not_leak_loop_variables() {
    local _out="$TEST_TEMP_DIR/leak-out" _name

    export SHADER_REPOS="https://example.com/a|alpha;https://example.com/b|beta"
    export SHADER_EFFECT_EXCLUDES="1|one.fx,two.fx"
    create_mock_shader_repo "alpha"
    mkdir -p "$_out"
    unset _repoList _allRepos _effectList dirName anyDir

    repoIsSelected "alpha,beta" alpha
    listConfiguredShaderRepoEntries >/dev/null
    listExcludedShaderEffectsForApp 1 >/dev/null
    mergeShaderDirsTo ReShade_shaders alpha "$_out"

    for _name in _repoList _allRepos _effectList dirName anyDir; do
        if [[ -n ${!_name+x} ]]; then
            echo "$_name leaked into the caller's scope" >&2
            return 1
        fi
    done
}

run_shader_tests() {
    echo -e "${BLUE}Shader Selection Tests${NC}"
    run_test "Header helpers exist before any merge runs" test_shader_header_helpers_exist_before_any_merge_runs
    run_test "Build with no repos or external shaders is quiet" test_shader_build_with_no_repos_and_no_external_shaders_is_quiet
    run_test "Helpers do not leak loop variables" test_helper_functions_do_not_leak_loop_variables
    run_test "Build creates output dir" test_shader_build_creates_dir
    run_test "Links only selected repo" test_shader_build_links_selected_repo
    run_test "Excludes unselected repo" test_shader_build_excludes_unselected_repo
    run_test "Includes .fxh from unselected repo" test_shader_build_includes_fxh_from_unselected_repo
    run_test "Includes external shaders" test_shader_build_includes_external
    run_test "Rebuild replaces previous" test_shader_rebuild_replaces_previous
    run_test "Build supports description without branch" test_shader_build_supports_description_without_branch
    run_test "Build mirrors root headers above shaders" test_shader_build_mirrors_root_headers_above_shaders
    run_test "Build exposes nested headers at shader root" test_shader_build_exposes_nested_headers_at_shader_root
    run_test "Build removes app-specific excluded effects" test_shader_build_removes_app_specific_excluded_effects
    run_test "Build keeps effects for other apps" test_shader_build_keeps_effects_for_other_apps
    run_test "Build discovers nested shader layouts" test_shader_build_discovers_nested_layouts
    run_test "Available repos only include existing dirs" test_shader_available_selected_repos_only_returns_existing_dirs
    run_test "CLI shader selection returns names only" test_shader_cli_selection_returns_names_only
    run_test "Auto-confirm keeps current shader selection" test_shader_auto_confirm_keeps_current_selection
    run_test "Auto-confirm defaults shader selection" test_shader_auto_confirm_defaults_to_all_repos_when_selection_is_empty
    run_test "Install first run defaults to curated subset" test_install_first_run_defaults_to_curated_subset
    run_test "YAD checklist accepts multiline output" test_shader_yad_selection_accepts_multiline_output
    run_test "Per-game ReShade.ini uses relative paths" test_game_ini_is_per_game_and_relative
    echo ""
}
