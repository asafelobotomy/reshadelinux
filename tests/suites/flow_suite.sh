#!/bin/bash

# UI helpers, dependency checks, ReShade download and batch-update flows.

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
    export RESHADE_VERSION=latest
    init_test_runtime_defaults
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
    init_test_runtime_defaults
    export RESHADE_VERSION=latest
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

run_flow_tests() {
    echo -e "${BLUE}UI, Dependency, Download and Batch Update Tests${NC}"
    run_test "Auto-confirm inputbox uses override" test_ui_inputbox_auto_confirm_uses_override_response
    run_test "Auto-confirm radiolist picks default" test_ui_radiolist_auto_confirm_returns_default_on_tag
    run_test "YAD progress returns after command finishes" test_with_progress_yad_returns_after_command_finishes
    run_test "UI capture preserves disabled errexit" test_ui_capture_preserves_errexit_disabled_state
    run_test "UI run preserves enabled errexit" test_ui_run_preserves_errexit_enabled_state
    run_test "Selection mode skips download-only tools" test_required_executables_selection_mode_skips_download_tools
    run_test "Install mode includes download tools" test_required_executables_install_mode_includes_download_tools
    run_test "ReShade update creates latest symlink" test_reshade_update_creates_latest_symlink_when_missing
    run_test "ReShade download rejects untrusted URL" test_download_reshade_rejects_untrusted_url
    run_test "Empty ReShade extraction fails" test_download_reshade_fails_when_extraction_is_empty
    run_test "ReShade download rejects hash mismatch" test_download_reshade_fails_when_hash_mismatches
    run_test "ReShade download rejects missing DLL payload" test_download_reshade_fails_when_payload_is_missing_dlls
    run_test "Batch update skips invalid state" test_batch_update_skips_invalid_state_file
    run_test "Batch update skips install prompt" test_batch_update_skips_install_prompt
    run_test "Batch update persists available shader subset" test_batch_update_persists_available_shader_subset
    run_test "Batch update honors CLI shader repo override" test_batch_update_honors_cli_shader_repo_override
    echo ""
}
