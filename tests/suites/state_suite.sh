#!/bin/bash

# Per-game state files, repo selection helpers and shader repo entry parsing.

test_state_write_and_read() {
    writeGameState "123456" "/games/mygame" "dxgi" "64" "sweetfx-shaders,immerse-shaders" "123456"
    local _f="$MAIN_PATH/game-state/123456.state"
    [[ -f "$_f" ]] || return 1
    grep -q '^dll=dxgi$' "$_f" || return 1
    grep -q '^arch=64$' "$_f" || return 1
    grep -q '^gamePath=/games/mygame$' "$_f" || return 1
    grep -q '^selected_repos=sweetfx-shaders,immerse-shaders$' "$_f" || return 1
    grep -q '^app_id=123456$' "$_f" || return 1
}

test_state_no_appid_is_noop() {
    local _count
    writeGameState "" "/games/mygame" "dxgi" "64" ""
    _count=$(find "$MAIN_PATH/game-state" -name "*.state" 2>/dev/null | wc -l)
    [[ "$_count" -eq 0 ]]
}

test_state_overwrite() {
    local _dll
    writeGameState "111" "/games/a" "d3d9" "32" "repo1" "111"
    writeGameState "111" "/games/b" "dxgi" "64" "repo2" "111"
    _dll=$(grep '^dll=' "$MAIN_PATH/game-state/111.state" | cut -d= -f2)
    [[ "$_dll" == "dxgi" ]]
}

test_state_builds_path_key_for_nonsteam_game() {
    local _key
    _key=$(buildGameInstallKey "" "/games/nonsteam")
    [[ "$_key" == path-* ]]
}

test_state_missing_selected_repos_defaults_to_all() {
    local _repos
    export SHADER_REPOS="https://example.com/a|alpha;https://example.com/b|beta"
    cat > "$MAIN_PATH/game-state/legacy.state" <<'EOF'
dll=dxgi
arch=64
gamePath=/games/legacy
EOF
    _repos=$(readSelectedReposFromState "$MAIN_PATH/game-state/legacy.state")
    [[ "$_repos" == "alpha,beta" ]]
}

test_state_explicit_empty_selected_repos_stays_empty() {
    local _repos
    export SHADER_REPOS="https://example.com/a|alpha;https://example.com/b|beta"
    writeGameState "empty" "/games/empty" "dxgi" "64" ""
    _repos=$(readSelectedReposFromState "$MAIN_PATH/game-state/empty.state")
    [[ -z "$_repos" ]]
}

test_state_can_read_named_field() {
    writeGameState "field" "/games/field" "dxgi" "64" "alpha,beta" "999"
    [[ "$(readGameStateField "$MAIN_PATH/game-state/field.state" dll)" == "dxgi" ]]
}

test_state_loader_reads_complete_state_payload() {
    local _dll="" _arch="" _game_path="" _selected_repos="" _app_id=""

    writeGameState "loaded" "/games/loaded" "d3d9" "32" "alpha,beta" "777"
    loadGameState "$MAIN_PATH/game-state/loaded.state" _dll _arch _game_path _selected_repos _app_id

    [[ "$_dll" == "d3d9" ]]
    [[ "$_arch" == "32" ]]
    [[ "$_game_path" == "/games/loaded" ]]
    [[ "$_selected_repos" == "alpha,beta" ]]
    [[ "$_app_id" == "777" ]]
}

test_state_checklist_marks_saved_repo_on() {
    local _state
    _state=$(repoChecklistState "alpha,beta" "alpha")
    [[ "$_state" == "ON" ]]
}

test_state_checklist_uses_exact_repo_match() {
    local _state
    _state=$(repoChecklistState "prod80-shaders" "prod80")
    [[ "$_state" == "OFF" ]]
}

test_state_detects_known_dll_override() {
    isKnownDllOverride "dxgi"
}

test_state_formats_installed_game_label() {
    local _game_dir="$TEST_TEMP_DIR/game-a"
    mkdir -p "$_game_dir"
    writeGameState "123456" "$_game_dir" "dxgi" "64" "alpha" "123456"
    ln -s /tmp/fake-dxgi "$_game_dir/dxgi.dll"
    [[ "$(formatDetectedGameLabel "Example Game" "123456" "$_game_dir")" == "✔ Example Game" ]]
}

test_state_default_repo_names_support_descriptions() {
    local _repos
    export SHADER_REPOS="https://example.com/a|alpha||Alpha Title|First repo;https://example.com/b|beta|main|Beta Title|Second repo"
    _repos=$(getDefaultSelectedRepos)
    [[ "$_repos" == "alpha,beta" ]]
}

test_state_first_run_repo_subset_prefers_curated_names() {
    local _repos
    export SHADER_REPOS="https://example.com/a|alpha||Alpha Title|First repo;https://example.com/b|beta|main|Beta Title|Second repo;https://example.com/c|gamma||Gamma Title|Third repo"
    export FIRST_RUN_SHADER_REPOS="beta,gamma,missing"
    _repos=$(getFirstRunSelectedRepos)
    [[ "$_repos" == "beta,gamma" ]]
}

test_state_first_run_repo_subset_falls_back_to_all_when_curated_names_missing() {
    local _repos
    export SHADER_REPOS="https://example.com/a|alpha||Alpha Title|First repo;https://example.com/b|beta|main|Beta Title|Second repo"
    export FIRST_RUN_SHADER_REPOS="missing-one,missing-two"
    _repos=$(getFirstRunSelectedRepos)
    [[ "$_repos" == "alpha,beta" ]]
}

test_state_shader_repo_parser_keeps_empty_branch_with_title_and_description() {
    local _shaderRepoUri="" _shaderRepoName="" _shaderRepoBranch="" _shaderRepoTitle="" _shaderRepoDesc=""
    export SHADER_REPOS="https://example.com/repo|alpha||Alpha Title|Description text"
    parseShaderRepoEntry "https://example.com/repo|alpha||Alpha Title|Description text"
    [[ "$_shaderRepoUri" == "https://example.com/repo" ]] || return 1
    [[ "$_shaderRepoName" == "alpha" ]] || return 1
    [[ -z "$_shaderRepoBranch" ]] || return 1
    [[ "$_shaderRepoTitle" == "Alpha Title" ]] || return 1
    [[ "$_shaderRepoDesc" == "Description text" ]]
}

test_state_shader_repo_parser_remains_backward_compatible_with_four_fields() {
    local _shaderRepoUri="" _shaderRepoName="" _shaderRepoBranch="" _shaderRepoTitle="" _shaderRepoDesc=""

    parseShaderRepoEntry "https://example.com/repo|alpha||Description text"
    [[ "$_shaderRepoUri" == "https://example.com/repo" ]] || return 1
    [[ "$_shaderRepoName" == "alpha" ]] || return 1
    [[ -z "$_shaderRepoBranch" ]] || return 1
    [[ "$_shaderRepoTitle" == "alpha" ]] || return 1
    [[ "$_shaderRepoDesc" == "Description text" ]]
}

test_state_shader_repo_parser_succeeds_with_title_and_description_under_set_e() {
    local _status
    set +e
    (
        set -e
        parseShaderRepoEntry "https://example.com/repo|alpha||Alpha Title|Description text"
        [[ "$_shaderRepoTitle" == "Alpha Title" ]]
        [[ "$_shaderRepoDesc" == "Description text" ]]
    )
    _status=$?
    set -e
    [[ $_status -eq 0 ]]
}

test_shader_display_label_includes_title_creator_and_summary() {
    local _label
    _label=$(formatShaderRepoDisplayLabel \
        "https://github.com/martymcmodding/qUINT" \
        "qUINT" \
        "Lightroom grading, SSR, MXAO, Bloom, Deband")
    [[ "$_label" == "qUINT by martymcmodding | Lightroom grading, SSR, MXAO, Bloom, Deband" ]]
}

run_state_tests() {
    echo -e "${BLUE}State Management Tests${NC}"
    run_test "Write and read state file" test_state_write_and_read
    run_test "No-op when appid empty" test_state_no_appid_is_noop
    run_test "State file overwrite" test_state_overwrite
    run_test "Non-Steam install key" test_state_builds_path_key_for_nonsteam_game
    run_test "Legacy state defaults to all repos" test_state_missing_selected_repos_defaults_to_all
    run_test "Explicit empty repo state stays empty" test_state_explicit_empty_selected_repos_stays_empty
    run_test "Read named state field" test_state_can_read_named_field
    run_test "Load complete state payload" test_state_loader_reads_complete_state_payload
    run_test "Checklist marks saved repo on" test_state_checklist_marks_saved_repo_on
    run_test "Checklist uses exact repo match" test_state_checklist_uses_exact_repo_match
    run_test "Recognizes known DLL override" test_state_detects_known_dll_override
    run_test "Formats installed game label" test_state_formats_installed_game_label
    run_test "Default repo parsing supports descriptions" test_state_default_repo_names_support_descriptions
    run_test "First-run subset prefers curated names" test_state_first_run_repo_subset_prefers_curated_names
    run_test "First-run subset falls back to all repos" test_state_first_run_repo_subset_falls_back_to_all_when_curated_names_missing
    run_test "Shader repo parser keeps empty branch" test_state_shader_repo_parser_keeps_empty_branch_with_title_and_description
    run_test "Shader repo parser stays backward compatible" test_state_shader_repo_parser_remains_backward_compatible_with_four_fields
    run_test "Shader repo parser succeeds under set -e" test_state_shader_repo_parser_succeeds_with_title_and_description_under_set_e
    run_test "Shader display label includes creator" test_shader_display_label_includes_title_creator_and_summary
    echo ""
}
