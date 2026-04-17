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

test_ui_inputbox_auto_confirm_uses_override_response() {
    local _output
    _output=$( (
        _UI_BACKEND=dialog
        UI_AUTO_CONFIRM=1
        UI_AUTO_INPUTBOX_RESPONSE="/tmp/reshade-game"
        ui_inputbox "ReShade" "Enter a directory path:" "/tmp/default"
    ) )

    [[ "$_output" == "/tmp/reshade-game" ]]
}

test_ui_radiolist_auto_confirm_returns_default_on_tag() {
    local _output
    _output=$( (
        _UI_BACKEND=dialog
        UI_AUTO_CONFIRM=1
        ui_radiolist "ReShade" "Pick one" 10 60 2 install "Install" ON uninstall "Uninstall" OFF
    ) )

    [[ "$_output" == "install" ]]
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
            printf '1\n2\n3\n'
        }
        selectShaders "alpha"
    ) )

    [[ "$_output" == "alpha,beta,gamma" ]]
}

test_ui_capture_preserves_errexit_disabled_state() {
    local _state
    _state=$( (
        set +e
        _UI_BACKEND=cli
        ui_capture bash -c 'exit 7' >/dev/null 2>&1 || true
        if [[ $- == *e* ]]; then
            printf 'on\n'
        else
            printf 'off\n'
        fi
    ) )

    [[ "$_state" == "off" ]]
}

test_ui_run_preserves_errexit_enabled_state() {
    local _state
    _state=$( (
        set -e
        _UI_BACKEND=cli
        ui_run true
        if [[ $- == *e* ]]; then
            printf 'on\n'
        else
            printf 'off\n'
        fi
    ) )

    [[ "$_state" == "on" ]]
}

test_required_executables_selection_mode_skips_download_tools() {
    local -a _required=()
    local _tool
    local _has_grep=0 _has_python3=0 _has_sed=0 _has_sha256sum=0
    local _has_curl=0 _has_7z=0 _has_file=0 _has_git=0

    mapfile -t _required < <(listRequiredExecutablesForMode selection)

    for _tool in "${_required[@]}"; do
        [[ $_tool == grep ]] && _has_grep=1
        [[ $_tool == python3 ]] && _has_python3=1
        [[ $_tool == sed ]] && _has_sed=1
        [[ $_tool == sha256sum ]] && _has_sha256sum=1
        [[ $_tool == curl ]] && _has_curl=1
        [[ $_tool == 7z ]] && _has_7z=1
        [[ $_tool == file ]] && _has_file=1
        [[ $_tool == git ]] && _has_git=1
    done

    [[ $_has_grep -eq 1 ]]
    [[ $_has_python3 -eq 1 ]]
    [[ $_has_sed -eq 1 ]]
    [[ $_has_sha256sum -eq 1 ]]
    [[ $_has_curl -eq 0 ]]
    [[ $_has_7z -eq 0 ]]
    [[ $_has_file -eq 0 ]]
    [[ $_has_git -eq 0 ]]
}

test_required_executables_install_mode_includes_download_tools() {
    local -a _required=()
    local _tool
    local _has_curl=0 _has_7z=0 _has_file=0 _has_git=0

    init_runtime_config

    mapfile -t _required < <(listRequiredExecutablesForMode install)

    for _tool in "${_required[@]}"; do
        [[ $_tool == curl ]] && _has_curl=1
        [[ $_tool == 7z ]] && _has_7z=1
        [[ $_tool == file ]] && _has_file=1
        [[ $_tool == git ]] && _has_git=1
    done

    [[ $_has_curl -eq 1 ]]
    [[ $_has_7z -eq 1 ]]
    [[ $_has_file -eq 1 ]]
    [[ $_has_git -eq 1 ]]
}

test_reshade_update_creates_latest_symlink_when_missing() {
    local _target
    (
        RESHADE_VERSION=latest
        RESHADE_ADDON_SUPPORT=0
        FORCE_RESHADE_UPDATE_CHECK=1
        UPDATE_RESHADE=1
        RESHADE_URL="https://reshade.example.invalid"
        RESHADE_URL_ALT="https://reshade-alt.example.invalid"

        curl() {
            printf '<a href="/downloads/ReShade_Setup_9.9.9.exe">download</a>'
        }

        withProgress() {
            local _text="$1"
            shift
            "$@"
        }

        downloadReshade() {
            local _version="$1"
            mkdir -p "$RESHADE_PATH/$_version"
            touch "$RESHADE_PATH/$_version/ReShade64.dll" "$RESHADE_PATH/$_version/ReShade32.dll"
        }

        ensureRequestedReshadeVersion
    ) || return 1
    [[ -L "$RESHADE_PATH/latest" ]] || return 1
    _target=$(readlink "$RESHADE_PATH/latest")
    [[ "$_target" == *"/9.9.9" ]]
}

test_download_reshade_rejects_untrusted_url() {
    set +e
    downloadReshade "1.2.3" "https://example.com/ReShade_Setup_1.2.3.exe" >/dev/null 2>&1
    local _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
}

test_download_reshade_fails_when_extraction_is_empty() {
    local _fake_bin="$TEST_TEMP_DIR/fakebin"
    mkdir -p "$_fake_bin"

    cat > "$_fake_bin/curl" <<'EOF'
#!/bin/bash
touch "${*: -1##*/}"
EOF
    cat > "$_fake_bin/file" <<'EOF'
#!/bin/bash
printf '%s: PE32 executable\n' "$1"
EOF
    cat > "$_fake_bin/7z" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$_fake_bin/curl" "$_fake_bin/file" "$_fake_bin/7z"

    PATH="$_fake_bin:$PATH"
    export PATH
    set +e
    downloadReshade "1.2.3" "https://reshade.me/downloads/ReShade_Setup_1.2.3.exe" >/dev/null 2>&1
    local _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
    [[ ! -e "$RESHADE_PATH/1.2.3/ReShade64.dll" ]]
}

test_download_reshade_fails_when_hash_mismatches() {
    local _fake_bin="$TEST_TEMP_DIR/fakebin-hash"
    mkdir -p "$_fake_bin"

    cat > "$_fake_bin/curl" <<'EOF'
#!/bin/bash
touch "${*: -1##*/}"
EOF
    cat > "$_fake_bin/file" <<'EOF'
#!/bin/bash
printf '%s: PE32 executable\n' "$1"
EOF
    chmod +x "$_fake_bin/curl" "$_fake_bin/file"

    PATH="$_fake_bin:$PATH"
    export PATH RESHADE_SETUP_SHA256=deadbeef
    set +e
    downloadReshade "1.2.3" "https://reshade.me/downloads/ReShade_Setup_1.2.3.exe" >/dev/null 2>&1
    local _rc=$?
    set -e
    unset RESHADE_SETUP_SHA256

    [[ $_rc -ne 0 ]]
}

test_download_reshade_fails_when_payload_is_missing_dlls() {
    local _fake_bin="$TEST_TEMP_DIR/fakebin-payload"
    mkdir -p "$_fake_bin"

    cat > "$_fake_bin/curl" <<'EOF'
#!/bin/bash
touch "${*: -1##*/}"
EOF
    cat > "$_fake_bin/file" <<'EOF'
#!/bin/bash
printf '%s: PE32 executable\n' "$1"
EOF
    cat > "$_fake_bin/7z" <<'EOF'
#!/bin/bash
touch not-reshade.txt
exit 0
EOF
    chmod +x "$_fake_bin/curl" "$_fake_bin/file" "$_fake_bin/7z"

    PATH="$_fake_bin:$PATH"
    export PATH
    set +e
    downloadReshade "1.2.3" "https://reshade.me/downloads/ReShade_Setup_1.2.3.exe" >/dev/null 2>&1
    local _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
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

test_batch_update_honors_cli_shader_repo_override() {
    local _game_dir="$TEST_TEMP_DIR/batch-cli-repos"
    mkdir -p "$MAIN_PATH/game-state" "$RESHADE_PATH/latest" "$_game_dir"
    touch "$RESHADE_PATH/latest/ReShade64.dll" "$RESHADE_PATH/latest/ReShade32.dll"
    touch "$MAIN_PATH/d3dcompiler_47.dll.64"
    export SHADER_REPOS="https://example.com/a|alpha;https://example.com/b|beta"
    create_mock_shader_repo "alpha"
    create_mock_shader_repo "beta"
    cat > "$MAIN_PATH/game-state/3000.state" <<EOF
dll=dxgi
arch=64
gamePath=$_game_dir
selected_repos=alpha
app_id=3000
EOF

    CLI_SHADER_REPOS="beta"
    CLI_SHADER_REPOS_SET=1
    _BATCH_UPDATE=1
    ( maybeHandleBatchUpdate ) >/dev/null 2>&1

    grep -q '^selected_repos=beta$' "$MAIN_PATH/game-state/3000.state"
    [[ -L "$MAIN_PATH/game-shaders/3000/Merged/Shaders/beta.fx" ]]
    [[ ! -e "$MAIN_PATH/game-shaders/3000/Merged/Shaders/alpha.fx" ]]
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

run_state_and_shader_tests() {
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

    echo -e "${BLUE}Release Metadata Tests${NC}"
    run_test "VERSION matches changelog current release" test_release_metadata_version_matches_changelog_headline
    run_test "Current changelog release is dated" test_release_metadata_current_version_is_dated
    echo ""

    echo -e "${BLUE}Shader Selection Tests${NC}"
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
    run_test "Auto-confirm inputbox uses override" test_ui_inputbox_auto_confirm_uses_override_response
    run_test "Auto-confirm radiolist picks default" test_ui_radiolist_auto_confirm_returns_default_on_tag
    run_test "YAD progress returns after command finishes" test_with_progress_yad_returns_after_command_finishes
    run_test "YAD checklist accepts multiline output" test_shader_yad_selection_accepts_multiline_output
    run_test "UI capture preserves disabled errexit" test_ui_capture_preserves_errexit_disabled_state
    run_test "UI run preserves enabled errexit" test_ui_run_preserves_errexit_enabled_state
    run_test "Selection mode skips download-only tools" test_required_executables_selection_mode_skips_download_tools
    run_test "Install mode includes download tools" test_required_executables_install_mode_includes_download_tools
    run_test "ReShade update creates latest symlink" test_reshade_update_creates_latest_symlink_when_missing
    run_test "ReShade download rejects untrusted URL" test_download_reshade_rejects_untrusted_url
    run_test "Empty ReShade extraction fails" test_download_reshade_fails_when_extraction_is_empty
    run_test "ReShade download rejects hash mismatch" test_download_reshade_fails_when_hash_mismatches
    run_test "ReShade download rejects missing DLL payload" test_download_reshade_fails_when_payload_is_missing_dlls
    run_test "Per-game ReShade.ini uses relative paths" test_game_ini_is_per_game_and_relative
    run_test "Batch update skips invalid state" test_batch_update_skips_invalid_state_file
    run_test "Batch update skips install prompt" test_batch_update_skips_install_prompt
    run_test "Batch update persists available shader subset" test_batch_update_persists_available_shader_subset
    run_test "Batch update honors CLI shader repo override" test_batch_update_honors_cli_shader_repo_override
    echo ""
}