#!/bin/bash

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
    export SHADER_REPOS="https://example.com/a|alpha||First repo;https://example.com/b|beta|main|Second repo"
    _repos=$(getDefaultSelectedRepos)
    [[ "$_repos" == "alpha,beta" ]]
}

test_state_shader_repo_parser_keeps_empty_branch_with_description() {
    local _shaderRepoUri="" _shaderRepoName="" _shaderRepoBranch="" _shaderRepoDesc=""
    export SHADER_REPOS="https://example.com/repo|alpha||Description text"
    parseShaderRepoEntry "https://example.com/repo|alpha||Description text"
    [[ "$_shaderRepoUri" == "https://example.com/repo" ]] || return 1
    [[ "$_shaderRepoName" == "alpha" ]] || return 1
    [[ -z "$_shaderRepoBranch" ]] || return 1
    [[ "$_shaderRepoDesc" == "Description text" ]]
}

test_state_shader_repo_parser_succeeds_with_description_under_set_e() {
    local _status
    set +e
    (
        set -e
        parseShaderRepoEntry "https://example.com/repo|alpha||Description text"
        [[ "$_shaderRepoDesc" == "Description text" ]]
    )
    _status=$?
    set -e
    [[ $_status -eq 0 ]]
}

test_shader_build_supports_description_without_branch() {
    export SHADER_REPOS="https://example.com/a|alpha||Alpha description"
    create_mock_shader_repo "alpha"
    buildGameShaderDir "55555" "alpha"
    [[ -L "$MAIN_PATH/game-shaders/55555/Merged/Shaders/alpha.fx" ]]
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

test_with_progress_yad_returns_after_command_finishes() {
    local _fake_bin="$TEST_TEMP_DIR/bin"
    local _pid _attempt

    mkdir -p "$_fake_bin"
    cat > "$_fake_bin/yad" <<'EOF'
#!/bin/bash
cat >/dev/null
EOF
    chmod +x "$_fake_bin/yad"

    PATH="$_fake_bin:$PATH"
    _UI_BACKEND=yad
    PROGRESS_UI=1
    export PATH PROGRESS_UI

    ( withProgress "Testing progress..." true ) &
    _pid=$!

    for _attempt in $(seq 1 20); do
        if ! kill -0 "$_pid" 2>/dev/null; then
            wait "$_pid"
            return $?
        fi
        sleep 0.1
    done

    kill "$_pid" 2>/dev/null || true
    wait "$_pid" 2>/dev/null || true
    return 1
}

test_shader_yad_selection_accepts_multiline_output() {
    local _output

    export SHADER_REPOS="https://example.com/a|alpha;https://example.com/b|beta;https://example.com/c|gamma"
    _output=$( (
        _UI_BACKEND=yad
        # shellcheck disable=SC2329
        ui_checklist() {
            printf 'alpha\nbeta\ngamma\n'
        }
        selectShaders "alpha"
    ) )

    [[ "$_output" == "alpha,beta,gamma" ]]
}

test_batch_update_skips_invalid_state_file() {
    local _game_dir="$TEST_TEMP_DIR/batch-invalid"
    mkdir -p "$MAIN_PATH/game-state" "$_game_dir"
    cat > "$MAIN_PATH/game-state/invalid.state" <<EOF
dll=not-a-dll
arch=wat
gamePath=$_game_dir
selected_repos=alpha
app_id=1000
EOF

    _BATCH_UPDATE=1
    local _output
    _output=$( ( maybeHandleBatchUpdate ) 2>&1 )
    [[ "$_output" == *"invalid or stale state file"* ]]
}

test_batch_update_skips_install_prompt() {
    local _output
    _output=$( (
        _BATCH_UPDATE=1
        _UI_BACKEND=cli
        # shellcheck disable=SC2329
        checkStdin() {
            printf 'prompted\n' >&2
            return 1
        }
        maybeHandleDirectXUninstall
    ) 2>&1 )
    [[ "$_output" != *"Do you want to (i)nstall or (u)ninstall ReShade"* ]]
}

test_batch_update_persists_available_shader_subset() {
    local _game_dir="$TEST_TEMP_DIR/batch-game"
    mkdir -p "$MAIN_PATH/game-state" "$RESHADE_PATH/latest" "$_game_dir"
    touch "$RESHADE_PATH/latest/ReShade64.dll" "$RESHADE_PATH/latest/ReShade32.dll"
    touch "$MAIN_PATH/d3dcompiler_47.dll.64"
    export SHADER_REPOS="https://example.com/a|alpha;https://example.com/b|beta"
    create_mock_shader_repo "alpha"
    cat > "$MAIN_PATH/game-state/2000.state" <<EOF
dll=dxgi
arch=64
gamePath=$_game_dir
selected_repos=alpha,beta
app_id=2000
EOF

    # shellcheck disable=SC2329
    ensureSelectedShaderRepos() {
        return 1
    }

    _BATCH_UPDATE=1
    ( maybeHandleBatchUpdate ) >/dev/null 2>&1
    grep -q '^selected_repos=alpha$' "$MAIN_PATH/game-state/2000.state"
    [[ -L "$_game_dir/ReShade_shaders" ]]
    [[ -L "$MAIN_PATH/game-shaders/2000/Merged/Shaders/alpha.fx" ]]
    [[ ! -e "$MAIN_PATH/game-shaders/2000/Merged/Shaders/beta.fx" ]]
}

test_release_metadata_version_matches_changelog_headline() {
    local version_file="$SCRIPT_DIR/../VERSION"
    local changelog_file="$SCRIPT_DIR/../CHANGELOG.md"
    local version changelog_version

    version=$(tr -d '\n' < "$version_file")
    changelog_version=$(grep -m1 '^## \[' "$changelog_file" | sed -E 's/^## \[([^]]+)\].*/\1/')

    [[ -n "$version" ]]
    [[ "$version" == "$changelog_version" ]]
}

test_release_metadata_current_version_is_dated() {
    local version_file="$SCRIPT_DIR/../VERSION"
    local changelog_file="$SCRIPT_DIR/../CHANGELOG.md"
    local version first_release_line

    version=$(tr -d '\n' < "$version_file")
    first_release_line=$(grep -m1 '^## \[' "$changelog_file")

    [[ "$first_release_line" == "## [$version] - "* ]]
    [[ "$first_release_line" != *"Unreleased"* ]]
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

run_state_and_shader_tests() {
    echo -e "${BLUE}State Management Tests${NC}"
    run_test "Write and read state file" test_state_write_and_read
    run_test "No-op when appid empty" test_state_no_appid_is_noop
    run_test "State file overwrite" test_state_overwrite
    run_test "Non-Steam install key" test_state_builds_path_key_for_nonsteam_game
    run_test "Legacy state defaults to all repos" test_state_missing_selected_repos_defaults_to_all
    run_test "Explicit empty repo state stays empty" test_state_explicit_empty_selected_repos_stays_empty
    run_test "Read named state field" test_state_can_read_named_field
    run_test "Checklist marks saved repo on" test_state_checklist_marks_saved_repo_on
    run_test "Checklist uses exact repo match" test_state_checklist_uses_exact_repo_match
    run_test "Recognizes known DLL override" test_state_detects_known_dll_override
    run_test "Formats installed game label" test_state_formats_installed_game_label
    run_test "Default repo parsing supports descriptions" test_state_default_repo_names_support_descriptions
    run_test "Shader repo parser keeps empty branch" test_state_shader_repo_parser_keeps_empty_branch_with_description
    run_test "Shader repo parser succeeds under set -e" test_state_shader_repo_parser_succeeds_with_description_under_set_e
    echo ""

    echo -e "${BLUE}Release Metadata Tests${NC}"
    run_test "VERSION matches changelog current release" test_release_metadata_version_matches_changelog_headline
    run_test "Current changelog release is dated" test_release_metadata_current_version_is_dated
    echo ""

    echo -e "${BLUE}Shader Selection Tests${NC}"
    run_test "Build creates output dir" test_shader_build_creates_dir
    run_test "Links only selected repo" test_shader_build_links_selected_repo
    run_test "Excludes unselected repo" test_shader_build_excludes_unselected_repo
    run_test "Includes external shaders" test_shader_build_includes_external
    run_test "Rebuild replaces previous" test_shader_rebuild_replaces_previous
    run_test "Build supports description without branch" test_shader_build_supports_description_without_branch
    run_test "Available repos only include existing dirs" test_shader_available_selected_repos_only_returns_existing_dirs
    run_test "CLI shader selection returns names only" test_shader_cli_selection_returns_names_only
    run_test "YAD progress returns after command finishes" test_with_progress_yad_returns_after_command_finishes
    run_test "YAD checklist accepts multiline output" test_shader_yad_selection_accepts_multiline_output
    run_test "Per-game ReShade.ini uses relative paths" test_game_ini_is_per_game_and_relative
    run_test "Batch update skips invalid state" test_batch_update_skips_invalid_state_file
    run_test "Batch update skips install prompt" test_batch_update_skips_install_prompt
    run_test "Batch update persists available shader subset" test_batch_update_persists_available_shader_subset
    echo ""
}