#!/bin/bash
# shellcheck disable=SC2030,SC2031  # PATH and other settings are changed inside subshells on purpose
# shellcheck disable=SC2016  # fake programs are written with their own, unexpanded, variables
# shellcheck disable=SC2034  # settings are set for the code under test

# Desktop integration: the clipboard tools and literal text in yad dialogs.

# Fake clipboard tools in their own directory. Each named tool records what it was given in
# $TEST_TEMP_DIR/clip-<tool>; a name ending in ":fail" makes that tool fail instead.
_install_clipboard_tools() {
    local _bin="$TEST_TEMP_DIR/clip-bin" _spec _tool _status
    mkdir -p "$_bin"
    for _spec in "$@"; do
        _tool="${_spec%%:*}"
        _status=0
        [[ $_spec == *:fail ]] && _status=1
        printf '#!/bin/sh\ncat > %q\nexit %d\n' "$TEST_TEMP_DIR/clip-$_tool" "$_status" > "$_bin/$_tool"
        chmod +x "$_bin/$_tool"
    done
    PATH="$_bin:/usr/bin:/bin"
}

_clip_received() {
    cat "$TEST_TEMP_DIR/clip-$1" 2>/dev/null
}

test_clipboard_uses_wl_copy_on_wayland() {
    _install_clipboard_tools wl-copy xclip
    WAYLAND_DISPLAY=wayland-0 DISPLAY=:0

    copyToClipboard 'launch %command%'

    [[ $(_clip_received wl-copy) == 'launch %command%' ]]
    [[ ! -e $TEST_TEMP_DIR/clip-xclip ]]
}

test_clipboard_falls_back_to_an_x_tool_when_wl_copy_fails() {
    _install_clipboard_tools wl-copy:fail xclip
    WAYLAND_DISPLAY=wayland-0 DISPLAY=:0

    copyToClipboard 'launch %command%'

    [[ $(_clip_received xclip) == 'launch %command%' ]]
}

test_clipboard_uses_xsel_when_xclip_is_missing() {
    _install_clipboard_tools xsel
    unset WAYLAND_DISPLAY
    DISPLAY=:0

    copyToClipboard 'launch %command%'

    [[ $(_clip_received xsel) == 'launch %command%' ]]
}

test_clipboard_reports_failure_without_a_display_or_a_tool() {
    _install_clipboard_tools xclip
    unset WAYLAND_DISPLAY DISPLAY
    assert_fails copyToClipboard 'text'

    _install_clipboard_tools
    DISPLAY=:0
    rm -f "$TEST_TEMP_DIR/clip-bin/xclip"
    assert_fails copyToClipboard 'text'
}

test_ui_quote_doubles_backslashes_for_yad_only() {
    _UI_BACKEND=yad
    [[ $(uiQuote 'C:\new\tab') == 'C:\\new\\tab' ]]
    _UI_BACKEND=whiptail
    [[ $(uiQuote 'C:\new\tab') == 'C:\new\tab' ]]
}

test_a_game_path_with_backslashes_reaches_yad_quoted() {
    local _bin="$TEST_TEMP_DIR/yad-bin" _game="$TEST_TEMP_DIR/odd\name"

    mkdir -p "$_bin"
    printf '#!/bin/bash\nfor a in "$@"; do printf "%%s\\n" "$a"; done > %q\n' "$TEST_TEMP_DIR/yad-args" > "$_bin/yad"
    chmod +x "$_bin/yad"
    PATH="$_bin:$PATH"
    _UI_BACKEND=yad

    ui_warnbox "ReShade" "Path does not exist:\n$(uiQuote "$_game")"
    grep -qxF -- "--text=Path does not exist:\\n$TEST_TEMP_DIR/odd\\\\name" "$TEST_TEMP_DIR/yad-args"

    ui_error "ReShade - Error" "Could not move '$_game' aside."
    grep -qxF -- "--text=Could not move '$TEST_TEMP_DIR/odd\\\\name' aside." "$TEST_TEMP_DIR/yad-args"
}

run_desktop_tests() {
    echo -e "${BLUE}Desktop Integration Tests${NC}"
    run_test "Clipboard uses wl-copy on Wayland" test_clipboard_uses_wl_copy_on_wayland
    run_test "Clipboard falls back when wl-copy fails" test_clipboard_falls_back_to_an_x_tool_when_wl_copy_fails
    run_test "Clipboard uses xsel without xclip" test_clipboard_uses_xsel_when_xclip_is_missing
    run_test "Clipboard fails without a display or tool" test_clipboard_reports_failure_without_a_display_or_a_tool
    run_test "uiQuote doubles backslashes for yad only" test_ui_quote_doubles_backslashes_for_yad_only
    run_test "Backslashes in a game path reach yad quoted" test_a_game_path_with_backslashes_reaches_yad_quoted
    echo ""
}
