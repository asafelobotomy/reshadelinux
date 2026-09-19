#!/bin/bash

# Dialog plumbing: yad text is plain text, and the auto-answer test hook announces itself.

# Put a fake yad first on PATH that records its arguments, one call per line.
_install_recording_yad() {
    local _stub="$TEST_TEMP_DIR/yad-bin" _log="$TEST_TEMP_DIR/yad-args.log"

    mkdir -p "$_stub"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$_log" > "$_stub/yad"
    chmod +x "$_stub/yad"
    printf '%s\n' "$_stub"
}

test_yad_message_dialogs_treat_text_as_plain_text() {
    local _stub _log="$TEST_TEMP_DIR/yad-args.log"

    _stub=$(_install_recording_yad)
    (
        PATH="$_stub:$PATH"
        _UI_BACKEND=yad
        ui_msgbox "Title" "Path: /games/Tom & Jerry <demo>" 10 60
        ui_yesno "Title" "Use /games/Tom & Jerry <demo>?" 10 60 || true
    )

    [[ $(grep -c -- '--info' "$_log") -eq 1 ]]
    [[ $(grep -c -- '--question' "$_log") -eq 1 ]]
    [[ $(grep -c -- '--no-markup' "$_log") -eq 2 ]]
}

test_fatal_error_dialog_treats_text_as_plain_text() {
    local _stub _log="$TEST_TEMP_DIR/yad-args.log"

    _stub=$(_install_recording_yad)
    (
        source "$REPO_DIR/lib/logging.sh"
        PATH="$_stub:$PATH"
        _UI_BACKEND=yad
        printErr "Use either --cli or --ui-backend=<backend>, not both."
    ) >/dev/null 2>&1 || true

    grep -q -- '--error' "$_log"
    grep -q -- '--no-markup' "$_log"
}

test_progress_dialog_keeps_its_intentional_markup() {
    grep -q '<tt>' "$REPO_DIR/lib/shaders.sh"
    ! grep -q -- '--no-markup' <(grep -n 'yad --progress' "$REPO_DIR/lib/utils.sh")
}

test_ui_auto_confirm_announces_itself_at_startup() {
    local _err

    _err=$( ( export UI_AUTO_CONFIRM=1; UI_BACKEND=cli init_runtime_config >/dev/null ) 2>&1 )
    [[ $_err == *"UI_AUTO_CONFIRM"* ]]
}

test_startup_is_silent_when_ui_auto_confirm_is_not_set() {
    local _err

    _err=$( ( unset UI_AUTO_CONFIRM; UI_BACKEND=cli init_runtime_config >/dev/null ) 2>&1 )
    [[ -z $_err ]]
}

run_ui_tests() {
    echo -e "${BLUE}UI Plumbing Tests${NC}"
    run_test "yad message dialogs use plain text" test_yad_message_dialogs_treat_text_as_plain_text
    run_test "yad fatal error dialog uses plain text" test_fatal_error_dialog_treats_text_as_plain_text
    run_test "Progress dialog keeps intentional markup" test_progress_dialog_keeps_its_intentional_markup
    run_test "UI_AUTO_CONFIRM announces itself" test_ui_auto_confirm_announces_itself_at_startup
    run_test "Startup is silent without UI_AUTO_CONFIRM" test_startup_is_silent_when_ui_auto_confirm_is_not_set
    echo ""
}
