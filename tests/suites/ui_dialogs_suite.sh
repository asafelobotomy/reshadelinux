#!/bin/bash
# shellcheck disable=SC2030,SC2031  # PATH and other settings are changed inside subshells on purpose
# shellcheck disable=SC2034  # variables are set for the code under test
# shellcheck disable=SC2016  # the searched-for text and the inner bash script are literal, not expanded here

# Dialog behaviour built on the recording fake yad of ui_suite.sh: select all / none in the shader
# picker, warning dialogs, and when output is coloured.

# ---- shader picker: select all / none ----

_checklist_calls() {
    local _sequence="$1"

    _stub=$(_install_recording_yad)
    (
        PATH="$_stub:$PATH"
        _UI_BACKEND=yad
        export YAD_STUB_SEQUENCE="$_sequence"
        ui_checklist "T" "Pick" 12 60 3 a "Alpha" ON b "Beta" OFF >/dev/null
    ) || _checklist_status=$?
}

test_yad_checklist_has_select_all_and_select_none_buttons_with_shortcuts() {
    local _stub _checklist_status=0 _log="$TEST_TEMP_DIR/yad-args.log"

    _checklist_calls "0"

    grep -q -- '--button=Select _all:10 --button=Select _none:11 --button=Cancel:1 --button=OK:0' "$_log"
}

test_yad_checklist_select_all_reopens_with_every_row_ticked() {
    local _stub _checklist_status=0 _log="$TEST_TEMP_DIR/yad-args.log"

    _checklist_calls "10 0"

    [[ $(wc -l < "$_log") -eq 2 ]]
    sed -n 1p "$_log" | grep -q 'TRUE a Alpha FALSE b Beta'
    sed -n 2p "$_log" | grep -q 'TRUE a Alpha TRUE b Beta'
}

test_yad_checklist_select_none_reopens_with_every_row_unticked() {
    local _stub _checklist_status=0 _log="$TEST_TEMP_DIR/yad-args.log"

    _checklist_calls "11 0"

    [[ $(wc -l < "$_log") -eq 2 ]]
    sed -n 2p "$_log" | grep -q 'FALSE a Alpha FALSE b Beta'
}

test_yad_checklist_select_all_then_none_uses_the_last_choice() {
    local _stub _checklist_status=0 _log="$TEST_TEMP_DIR/yad-args.log"

    _checklist_calls "10 11 0"

    [[ $(wc -l < "$_log") -eq 3 ]]
    sed -n 3p "$_log" | grep -q 'FALSE a Alpha FALSE b Beta'
}

test_yad_checklist_cancel_ends_without_reopening() {
    local _stub _checklist_status=0 _log="$TEST_TEMP_DIR/yad-args.log"

    _checklist_calls "1"

    [[ $(wc -l < "$_log") -eq 1 ]]
    [[ $_checklist_status -ne 0 ]]
}

test_yad_checklist_ok_returns_the_selection_without_reopening() {
    local _stub _checklist_status=0 _log="$TEST_TEMP_DIR/yad-args.log"

    _checklist_calls "0"

    [[ $(wc -l < "$_log") -eq 1 && $_checklist_status -eq 0 ]]
}

# ---- warnings get a warning icon ----

test_yad_warning_dialog_uses_a_warning_icon_and_an_ok_button() {
    local _stub _log="$TEST_TEMP_DIR/yad-args.log"

    _stub=$(_install_recording_yad)
    (
        PATH="$_stub:$PATH"
        _UI_BACKEND=yad
        ui_warnbox "T" "Careful" 10 60
    )

    grep -q -- '--image=dialog-warning' "$_log"
    grep -q -- '--button=OK:0' "$_log"
    grep -q -- '--no-markup' "$_log"
}

test_warning_dialog_is_a_plain_message_box_on_the_terminal_backends_and_silent_on_cli() {
    local _bin="$TEST_TEMP_DIR/tui-bin" _log="$TEST_TEMP_DIR/tui.log"

    mkdir -p "$_bin"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$_log" > "$_bin/whiptail"
    chmod +x "$_bin/whiptail"
    (
        PATH="$_bin:$PATH"
        _UI_BACKEND=whiptail
        # without a controlling terminal whiptail's screen refresh fails; only the call matters
        ui_warnbox "T" "Careful" 10 60 || true
        _UI_BACKEND=cli
        ui_warnbox "T" "Careful" 10 60
    )

    [[ $(wc -l < "$_log") -eq 1 ]]
    grep -q -- '--msgbox Careful' "$_log"
}

test_the_messages_that_warn_use_the_warning_dialog() {
    grep -q 'ui_warnbox "ReShade" "Path does not exist' "$REPO_DIR/lib/game_selection.sh"
    grep -q 'ui_warnbox "ReShade" "'"'"'$wantedDll'"'"' is not a supported DLL override' "$REPO_DIR/lib/install.sh"
    grep -q 'ui_warnbox "ReShade - Download Error" "Some shader repositories could not be downloaded' "$REPO_DIR/lib/flow.sh"
}

# ---- colour ----

# Prints "coloured" or "plain" for printStep, run with stdout captured (so not a terminal).
_colour_probe() {
    local _out

    _out=$(env "$@" bash -c 'source "$1/lib/logging.sh"; printStep hello' _ "$REPO_DIR")
    if [[ $_out == *$'\e['* ]]; then echo coloured; else echo plain; fi
}

test_output_is_plain_when_it_is_not_a_terminal() {
    [[ $(_colour_probe) == plain ]]
}

test_no_color_switches_colour_off_even_when_it_is_forced() {
    [[ $(_colour_probe NO_COLOR=1 CLICOLOR_FORCE=1) == plain ]]
}

test_clicolor_force_switches_colour_on_for_a_pipe() {
    [[ $(_colour_probe CLICOLOR_FORCE=1) == coloured ]]
}

# The same command on a pseudo terminal: prints "coloured" or "plain". The child's own output is
# sent to /dev/null so that only the verdict reaches the caller.
_terminal_colour_probe() {
    python3 - "$REPO_DIR" <<'PTYEOF'
import os, pty, sys
seen = []
def read(fd):
    data = os.read(fd, 4096)
    seen.append(data)
    return data
saved = os.dup(1)
os.dup2(os.open(os.devnull, os.O_WRONLY), 1)
pty.spawn(["bash", "-c", 'source "$1/lib/logging.sh"; printStep hello', "_", sys.argv[1]], read)
os.dup2(saved, 1)
print("coloured" if b"\x1b[" in b"".join(seen) else "plain")
PTYEOF
}

test_output_is_coloured_on_a_real_terminal_unless_no_color_is_set() {
    [[ $(_terminal_colour_probe) == coloured ]]
    [[ $(NO_COLOR=1 _terminal_colour_probe) == plain ]]
}

run_ui_dialog_tests() {
    echo -e "${BLUE}UI Dialog Behaviour Tests${NC}"
    run_test "yad checklist has select all and none buttons" test_yad_checklist_has_select_all_and_select_none_buttons_with_shortcuts
    run_test "Select all reopens with every row ticked" test_yad_checklist_select_all_reopens_with_every_row_ticked
    run_test "Select none reopens with every row unticked" test_yad_checklist_select_none_reopens_with_every_row_unticked
    run_test "The last of several select choices wins" test_yad_checklist_select_all_then_none_uses_the_last_choice
    run_test "Cancel ends the checklist without reopening" test_yad_checklist_cancel_ends_without_reopening
    run_test "OK returns the checklist without reopening" test_yad_checklist_ok_returns_the_selection_without_reopening
    run_test "Warning dialog uses a warning icon" test_yad_warning_dialog_uses_a_warning_icon_and_an_ok_button
    run_test "Warning dialog on terminal backends and cli" test_warning_dialog_is_a_plain_message_box_on_the_terminal_backends_and_silent_on_cli
    run_test "Warning messages use the warning dialog" test_the_messages_that_warn_use_the_warning_dialog
    run_test "Output is plain when not a terminal" test_output_is_plain_when_it_is_not_a_terminal
    run_test "NO_COLOR beats CLICOLOR_FORCE" test_no_color_switches_colour_off_even_when_it_is_forced
    run_test "CLICOLOR_FORCE colours a pipe" test_clicolor_force_switches_colour_on_for_a_pipe
    run_test "Colour on a real terminal unless NO_COLOR" test_output_is_coloured_on_a_real_terminal_unless_no_color_is_set
    echo ""
}
