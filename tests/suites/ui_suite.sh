#!/bin/bash
# shellcheck disable=SC2030,SC2031  # PATH and other settings are changed inside subshells on purpose

# Dialog plumbing: yad text is plain text, and the auto-answer test hook announces itself.

# Put a fake yad first on PATH that records its arguments, one call per line. It rejects
# the dialog kinds that yad 15 removed (--info, --question, --error, --warning) exactly as the
# real program does, so a wrapper that still uses them fails here instead of on a user's desktop.
# YAD_STUB_STATUS sets the exit status of an accepted call; YAD_STUB_STDERR is printed to stderr.
_install_recording_yad() {
    local _stub="$TEST_TEMP_DIR/yad-bin" _log="$TEST_TEMP_DIR/yad-args.log"

    mkdir -p "$_stub"
    cat > "$_stub/yad" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$_log"
for _arg in "\$@"; do
    case "\$_arg" in
        --info|--question|--error|--warning)
            echo "Unable to parse command line: Unknown option \$_arg" >&2
            exit 1 ;;
    esac
done
[ -n "\${YAD_STUB_STDERR:-}" ] && printf '%s\n' "\$YAD_STUB_STDERR" >&2
exit "\${YAD_STUB_STATUS:-0}"
EOF
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

    [[ $(grep -c -- '--no-markup' "$_log") -eq 2 ]]
    [[ $(grep -c -- '--button=OK:0' "$_log") -eq 1 ]]
    [[ $(grep -c -- '--button=Yes:0' "$_log") -eq 1 ]]
}

test_yad_yesno_lists_yes_first_so_enter_answers_yes_like_the_terminal_backends() {
    local _stub _log="$TEST_TEMP_DIR/yad-args.log"

    _stub=$(_install_recording_yad)
    (
        PATH="$_stub:$PATH"
        _UI_BACKEND=yad
        ui_yesno "T" "Q" 10 60
    )

    grep -q -- '--button=Yes:0 --button=No:1' "$_log"
}

test_yad_message_dialogs_use_only_options_every_yad_version_accepts() {
    local _stub _log="$TEST_TEMP_DIR/yad-args.log"

    _stub=$(_install_recording_yad)
    (
        PATH="$_stub:$PATH"
        _UI_BACKEND=yad
        ui_msgbox "Title" "Done" 10 60
        ui_yesno "Title" "Sure?" 10 60
        ui_error "Title" "Broken"
    )

    [[ $(wc -l < "$_log") -eq 3 ]]
    assert_fails grep -qE -- '--(info|question|error|warning)( |$)' "$_log"
    grep -q -- '--image=dialog-information' "$_log"
    grep -q -- '--image=dialog-question' "$_log"
    grep -q -- '--image=dialog-error' "$_log"
}

test_yad_yesno_maps_button_and_close_to_an_answer() {
    local _stub

    _stub=$(_install_recording_yad)
    (
        PATH="$_stub:$PATH"
        _UI_BACKEND=yad
        YAD_STUB_STATUS=0 ui_yesno "T" "Q" 10 60
        export YAD_STUB_STATUS=1
        assert_fails ui_yesno "T" "Q" 10 60
        export YAD_STUB_STATUS=252
        assert_fails ui_yesno "T" "Q" 10 60
    )
}

test_yad_complaints_are_logged_instead_of_thrown_away() {
    local _stub _debugLog="$TEST_TEMP_DIR/debug.log"

    _stub=$(_install_recording_yad)
    (
        source "$REPO_DIR/lib/logging.sh"
        PATH="$_stub:$PATH"
        _UI_BACKEND=yad
        RESHADE_DEBUG_LOG="$_debugLog"
        YAD_STUB_STDERR="Gtk-WARNING: something odd" ui_msgbox "T" "Body" 10 60
        YAD_STUB_STDERR="Gtk-WARNING: from a list" ui_menu "T" "Pick" 10 60 3 a "A" b "B" || true
    )

    grep -q "Gtk-WARNING: something odd" "$_debugLog"
    grep -q "Gtk-WARNING: from a list" "$_debugLog"
}

# In a yad radio list the answer is the radio button, which moves only when its own cell is
# clicked: clicking a label and pressing OK returned the pre-selected option. A plain list
# answers with the highlighted row instead.
test_yad_radiolist_answers_with_the_highlighted_row_not_a_radio_button() {
    local _stub _log="$TEST_TEMP_DIR/yad-args.log"

    _stub=$(_install_recording_yad)
    (
        PATH="$_stub:$PATH"
        _UI_BACKEND=yad
        ui_radiolist "T" "Pick" 12 60 3 install "Install it" ON uninstall "Uninstall it" OFF update "Update <all>" OFF >/dev/null
    )

    assert_fails grep -q -- '--radiolist' "$_log"
    grep -q -- '--hide-column=1' "$_log"
    grep -q -- '--print-column=1' "$_log"
    grep -q -- 'install Install it uninstall Uninstall it update Update &lt;all&gt;' "$_log"
}

test_yad_radiolist_lists_the_default_option_first_because_yad_highlights_the_first_row() {
    local _stub _log="$TEST_TEMP_DIR/yad-args.log"

    _stub=$(_install_recording_yad)
    (
        PATH="$_stub:$PATH"
        _UI_BACKEND=yad
        ui_radiolist "T" "Pick" 12 60 3 dxgi "dxgi" OFF d3d11 "d3d11" ON opengl32 "opengl32" OFF >/dev/null
    )

    grep -q -- 'd3d11 d3d11 dxgi dxgi opengl32 opengl32' "$_log"
}

test_yad_menu_hides_its_key_column() {
    local _stub _log="$TEST_TEMP_DIR/yad-args.log"

    _stub=$(_install_recording_yad)
    (
        PATH="$_stub:$PATH"
        _UI_BACKEND=yad
        ui_menu "T" "Pick" 12 60 3 a "First" b "Second" >/dev/null
    )

    grep -q -- '--hide-column=1' "$_log"
}

test_yad_dialogs_still_open_when_mktemp_fails() {
    local _stub _log="$TEST_TEMP_DIR/yad-args.log"

    _stub=$(_install_recording_yad)
    printf '#!/bin/sh\nexit 1\n' > "$_stub/mktemp"
    chmod +x "$_stub/mktemp"
    (
        PATH="$_stub:$PATH"
        _UI_BACKEND=yad
        ui_msgbox "T" "Body" 10 60
        ui_menu "T" "Pick" 10 60 3 a "A" b "B" >/dev/null
    )

    [[ $(wc -l < "$_log") -eq 2 ]]
}

test_ui_error_is_a_no_op_when_no_backend_is_set() {
    (
        set -u
        unset _UI_BACKEND
        ui_error "T" "Body"
    )
}

test_pango_escape_escapes_markup_characters_on_every_bash_version() {
    [[ $(_pango_escape 'Tom & Jerry <demo> >') == 'Tom &amp; Jerry &lt;demo&gt; &gt;' ]]
    [[ $(_pango_escape 'plain') == 'plain' ]]
    [[ $(_pango_escape '&amp;') == '&amp;amp;' ]]
    (
        # Bash 5.2 reads an unquoted & in a replacement as the matched text.
        shopt -s patsub_replacement 2>/dev/null || exit 0
        [[ $(_pango_escape 'a<b>&c') == 'a&lt;b&gt;&amp;c' ]]
    )
    (
        shopt -u patsub_replacement 2>/dev/null || exit 0
        [[ $(_pango_escape 'a<b>&c') == 'a&lt;b&gt;&amp;c' ]]
    )
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

    [[ $(wc -l < "$_log") -eq 1 ]]
    grep -q -- '--image=dialog-error' "$_log"
    grep -q -- '--no-markup' "$_log"
    grep -q -- '--button=Close:0' "$_log"
}

test_no_source_file_uses_a_yad_dialog_kind_that_yad_15_removed() {
    assert_fails grep -rnE 'yad +--(info|question|error|warning)\b' "$REPO_DIR/lib" "$REPO_DIR/reshadelinux.sh" "$REPO_DIR/reshadelinux-gui.sh"
}

test_progress_dialog_keeps_its_intentional_markup() {
    grep -q '<tt>' "$REPO_DIR/lib/shaders.sh"
    assert_fails grep -q -- '--no-markup' <(grep -n 'yad --progress' "$REPO_DIR/lib/utils.sh")
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
    run_test "yad yes/no answers Yes on Enter like the TUI" test_yad_yesno_lists_yes_first_so_enter_answers_yes_like_the_terminal_backends
    run_test "yad message dialogs use options every yad accepts" test_yad_message_dialogs_use_only_options_every_yad_version_accepts
    run_test "yad yes/no maps buttons and close to an answer" test_yad_yesno_maps_button_and_close_to_an_answer
    run_test "yad complaints are logged, not discarded" test_yad_complaints_are_logged_instead_of_thrown_away
    run_test "yad radio list answers with the highlighted row" test_yad_radiolist_answers_with_the_highlighted_row_not_a_radio_button
    run_test "yad radio list puts the default option first" test_yad_radiolist_lists_the_default_option_first_because_yad_highlights_the_first_row
    run_test "yad menu hides its key column" test_yad_menu_hides_its_key_column
    run_test "Pango escaping is correct on every bash version" test_pango_escape_escapes_markup_characters_on_every_bash_version
    run_test "yad fatal error dialog uses plain text" test_fatal_error_dialog_treats_text_as_plain_text
    run_test "No source uses a removed yad dialog kind" test_no_source_file_uses_a_yad_dialog_kind_that_yad_15_removed
    run_test "Progress dialog keeps intentional markup" test_progress_dialog_keeps_its_intentional_markup
    run_test "UI_AUTO_CONFIRM announces itself" test_ui_auto_confirm_announces_itself_at_startup
    run_test "Startup is silent without UI_AUTO_CONFIRM" test_startup_is_silent_when_ui_auto_confirm_is_not_set
    run_test "yad dialogs still open when mktemp fails" test_yad_dialogs_still_open_when_mktemp_fails
    run_test "ui_error needs no backend variable" test_ui_error_is_a_no_op_when_no_backend_is_set
    echo ""
}
