#!/bin/bash
# shellcheck disable=SC2030,SC2031  # settings are changed inside subshells on purpose
# shellcheck disable=SC2317,SC2329  # test functions and stubs are invoked indirectly
# shellcheck disable=SC2016  # the fake programs are written as literal shell text

# How the graphical interface is started: the reshadelinux-gui.sh wrapper (with fake terminal
# emulators and a fake notifier) and the yad smoke tooling that runs without a display.

# ---- reshadelinux-gui.sh: what happens when yad is missing ----

# A copy of the wrapper next to a fake entrypoint that reports how it was started, and a PATH
# holding only the tools the wrapper needs plus whatever fakes the test adds.
_make_wrapper_sandbox() {
    local _dir="$TEST_TEMP_DIR/wrapper" _bin="$TEST_TEMP_DIR/wrapper-bin" _tool

    mkdir -p "$_dir" "$_bin"
    cp "$REPO_DIR/reshadelinux-gui.sh" "$_dir/reshadelinux-gui.sh"
    cat > "$_dir/reshadelinux.sh" <<'ENTRY'
#!/usr/bin/env bash
printf 'BACKEND=%s IN_TERMINAL=%s ARGS=%s\n' "$UI_BACKEND" "${RESHADELINUX_IN_TERMINAL:-}" "$*"
exit "${FAKE_ENTRY_STATUS:-0}"
ENTRY
    chmod +x "$_dir/reshadelinux.sh"
    for _tool in bash dirname env cat mktemp rm; do
        ln -sf "$(command -v "$_tool")" "$_bin/$_tool"
    done
}

# A fake program on the sandbox PATH that records its arguments and the environment flag.
_add_fake_program() {
    local _name="$1" _log="$TEST_TEMP_DIR/wrapper-$1.log"

    printf '#!/bin/sh\nprintf "%%s|IN_TERMINAL=%%s\\n" "$*" "${RESHADELINUX_IN_TERMINAL:-}" >> "%s"\nexit 0\n' "$_log" > "$TEST_TEMP_DIR/wrapper-bin/$_name"
    chmod +x "$TEST_TEMP_DIR/wrapper-bin/$_name"
}

# A menu launch passes no arguments, so that is what the terminal-fallback tests do; a run with
# arguments is a script or a shortcut and is covered by _run_wrapper_with_arguments.
_run_wrapper() {
    env -i PATH="$TEST_TEMP_DIR/wrapper-bin" HOME="$TEST_TEMP_DIR" "$@" \
        "$TEST_TEMP_DIR/wrapper/reshadelinux-gui.sh" 2>&1 </dev/null
}

_run_wrapper_with_arguments() {
    env -i PATH="$TEST_TEMP_DIR/wrapper-bin" HOME="$TEST_TEMP_DIR" "$@" \
        "$TEST_TEMP_DIR/wrapper/reshadelinux-gui.sh" --update-all 2>&1 </dev/null
}

test_wrapper_uses_yad_when_it_is_installed() {
    local _output

    _make_wrapper_sandbox
    _add_fake_program yad
    _add_fake_program xterm

    _output=$(_run_wrapper DISPLAY=:0)

    [[ $_output == *"BACKEND=yad"* ]]
    [[ ! -e $TEST_TEMP_DIR/wrapper-xterm.log ]]
}

test_wrapper_opens_a_terminal_when_yad_is_missing_and_launched_from_the_desktop() {
    local _output

    _make_wrapper_sandbox
    _add_fake_program xterm

    _output=$(_run_wrapper DISPLAY=:0)

    [[ $_output != *"BACKEND="* ]]
    grep -q -- '^-e bash -c ' "$TEST_TEMP_DIR/wrapper-xterm.log"
    grep -q -- 'reshadelinux-gui.sh' "$TEST_TEMP_DIR/wrapper-xterm.log"
    grep -q 'IN_TERMINAL=1' "$TEST_TEMP_DIR/wrapper-xterm.log"
}

test_wrapper_holds_the_terminal_open_so_the_result_can_be_read() {
    _make_wrapper_sandbox
    _add_fake_program xterm

    _run_wrapper DISPLAY=:0 >/dev/null

    grep -q 'Press Enter to close' "$TEST_TEMP_DIR/wrapper-xterm.log"
}

test_wrapper_uses_each_terminals_own_way_to_run_a_command_and_wait() {
    local _term _expected _output

    for _term in gnome-terminal konsole xfce4-terminal kitty; do
        _make_wrapper_sandbox
        rm -f "$TEST_TEMP_DIR"/wrapper-bin/*term* "$TEST_TEMP_DIR"/wrapper-bin/kitty "$TEST_TEMP_DIR"/wrapper-bin/konsole
        _add_fake_program "$_term"
        _run_wrapper DISPLAY=:0 >/dev/null
        case $_term in
            gnome-terminal) _expected='^--wait -- bash -c ' ;;
            konsole) _expected='^--nofork -e bash -c ' ;;
            xfce4-terminal) _expected='^--disable-server -x bash -c ' ;;
            kitty) _expected='^bash -c ' ;;
        esac
        grep -q -- "$_expected" "$TEST_TEMP_DIR/wrapper-$_term.log" || { echo "$_term: wrong arguments" >&2; return 1; }
        rm -f "$TEST_TEMP_DIR/wrapper-$_term.log"
    done
}

test_wrapper_passes_on_the_installers_exit_status_and_does_not_start_it_again_elsewhere() {
    local _status=0

    # kitty comes before xterm in the wrapper's list, so kitty is the emulator that runs.
    _make_wrapper_sandbox
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit 3\n' "$TEST_TEMP_DIR/wrapper-kitty.log" > "$TEST_TEMP_DIR/wrapper-bin/kitty"
    chmod +x "$TEST_TEMP_DIR/wrapper-bin/kitty"
    _add_fake_program xterm

    _run_wrapper DISPLAY=:0 >/dev/null || _status=$?

    [[ $_status -eq 3 ]]
    [[ -s $TEST_TEMP_DIR/wrapper-kitty.log ]]
    [[ ! -e $TEST_TEMP_DIR/wrapper-xterm.log ]]
}

# Some emulators (xterm among them) exit 0 whatever their command returned, so the wrapper cannot
# rely on the emulator's status: the run inside the terminal records the installer's own.
test_wrapper_reports_the_installers_status_even_when_the_terminal_always_exits_zero() {
    local _status=0

    _make_wrapper_sandbox
    # a terminal that really runs its command (after the -e flag) but always exits 0, like xterm
    printf '#!/bin/sh\nshift\n"$@" </dev/null >/dev/null 2>&1\nexit 0\n' > "$TEST_TEMP_DIR/wrapper-bin/xterm"
    chmod +x "$TEST_TEMP_DIR/wrapper-bin/xterm"

    _run_wrapper DISPLAY=:0 FAKE_ENTRY_STATUS=4 >/dev/null || _status=$?

    [[ $_status -eq 4 ]]
}

test_wrapper_returns_zero_when_the_run_in_the_terminal_succeeds() {
    _make_wrapper_sandbox
    printf '#!/bin/sh\nshift\n"$@" </dev/null >/dev/null 2>&1\nexit 0\n' > "$TEST_TEMP_DIR/wrapper-bin/xterm"
    chmod +x "$TEST_TEMP_DIR/wrapper-bin/xterm"

    _run_wrapper DISPLAY=:0 FAKE_ENTRY_STATUS=0 >/dev/null
}

test_wrapper_moves_on_when_a_terminal_cannot_be_started() {
    local _status=0

    # kitty (first in the list) cannot run at all, so the wrapper falls through to xterm.
    _make_wrapper_sandbox
    printf '#!/bin/sh\nexit 127\n' > "$TEST_TEMP_DIR/wrapper-bin/kitty"
    chmod +x "$TEST_TEMP_DIR/wrapper-bin/kitty"
    _add_fake_program xterm

    _run_wrapper DISPLAY=:0 >/dev/null || _status=$?

    [[ $_status -eq 0 ]]
    grep -q -- '-e bash -c' "$TEST_TEMP_DIR/wrapper-xterm.log"
}

test_yad_smoke_keeps_its_workspace_and_reports_a_failing_exit_status() {
    local _root="$TEST_TEMP_DIR/smoke-fail-ws" _output _status=0

    mkdir -p "$_root/case"
    printf 'the reason\n' > "$_root/case/scenario.log"
    _output=$(
        (
            source "$REPO_DIR/scripts/diagnostics/helpers/smoke_yad_common.sh"
            # shellcheck disable=SC2064  # expand the path now, when the trap is set
            trap "yadsmoke_finish '$_root'" EXIT
            exit 3
        ) 2>&1
    ) || _status=$?

    [[ $_status -eq 3 ]]
    [[ -d $_root/case ]]
    [[ $_output == *"SMOKE_RESULT=FAIL"* && $_output == *"the reason"* ]]
}

test_yad_smoke_removes_its_workspace_after_a_passing_run() {
    local _root="$TEST_TEMP_DIR/smoke-pass-ws"

    mkdir -p "$_root/case"
    (
        source "$REPO_DIR/scripts/diagnostics/helpers/smoke_yad_common.sh"
        # shellcheck disable=SC2064  # expand the path now, when the trap is set
        trap "yadsmoke_finish '$_root'" EXIT
        exit 0
    ) >/dev/null 2>&1

    [[ ! -e $_root ]]
}

# A progress window is titled like the dialogs around it and appears between them, so the driver
# must tell it apart by the command line of its process. (The checks run in a plain subshell: on
# the left of || errexit would be off and the assertions could not fail the test.)
test_yad_smoke_recognises_a_progress_window_by_its_process() {
    (
        source "$REPO_DIR/scripts/diagnostics/helpers/smoke_yad_common.sh"
        bash -c 'sleep 30; true' --progress --pulsate &
        _progress=$!
        bash -c 'sleep 30; true' --info-only &
        _dialog=$!
        trap 'kill "$_progress" "$_dialog" 2>/dev/null' EXIT

        yadsmoke_pid_is_progress "$_progress"
        assert_fails yadsmoke_pid_is_progress "$_dialog"
        assert_fails yadsmoke_pid_is_progress 99999999
    )
}

test_smoke_failure_report_skips_binary_logs() {
    local _root="$TEST_TEMP_DIR/smoke-binary-ws" _output

    mkdir -p "$_root/home"
    printf 'readable reason\n' > "$_root/scenario.log"
    printf '\000\001\002binary-marker\377\376\000\000' > "$_root/home/journal.log"
    _output=$(
        (
            source "$REPO_DIR/scripts/diagnostics/helpers/smoke_common.sh"
            # shellcheck disable=SC2064  # expand the path now, when the trap is set
            trap "smoke_finish '$_root'" EXIT
            exit 1
        ) 2>&1
    ) || true

    [[ $_output == *"readable reason"* ]]
    [[ $_output != *"binary-marker"* ]]
}

test_yad_smoke_never_kills_yad_windows_it_did_not_start() {
    assert_fails grep -nE 'pkill|killall' "$REPO_DIR/scripts/diagnostics/smoke_yad.sh" "$REPO_DIR/scripts/diagnostics/helpers/smoke_yad_common.sh"
}

test_wrapper_does_not_open_a_second_terminal_from_inside_one() {
    local _output

    _make_wrapper_sandbox
    _add_fake_program xterm

    _output=$(_run_wrapper DISPLAY=:0 RESHADELINUX_IN_TERMINAL=1)

    [[ $_output == *"BACKEND=auto"* ]]
    [[ ! -e $TEST_TEMP_DIR/wrapper-xterm.log ]]
}

# A menu launch has no arguments. A script (the release tool's `--update-all` check, cron) does, and
# it must never get a terminal window that waits for Enter.
test_wrapper_never_opens_a_terminal_for_a_scripted_run_with_arguments() {
    local _output

    _make_wrapper_sandbox
    _add_fake_program xterm

    _output=$(_run_wrapper_with_arguments DISPLAY=:0)

    [[ $_output == *"BACKEND=auto"* && $_output == *"ARGS=--update-all"* ]]
    [[ ! -e $TEST_TEMP_DIR/wrapper-xterm.log ]]
}

test_wrapper_does_nothing_special_without_a_display() {
    local _output

    _make_wrapper_sandbox
    _add_fake_program xterm

    _output=$(_run_wrapper)

    [[ $_output == *"BACKEND=auto"* ]]
    [[ ! -e $TEST_TEMP_DIR/wrapper-xterm.log ]]
}

test_wrapper_tells_the_desktop_user_when_there_is_no_terminal_either() {
    local _output

    _make_wrapper_sandbox
    _add_fake_program notify-send

    _output=$(_run_wrapper DISPLAY=:0)

    grep -q 'yad' "$TEST_TEMP_DIR/wrapper-notify-send.log"
    [[ $_output == *"BACKEND=auto"* ]]
}

# ---- scripts/diagnostics/smoke_yad.sh ----

test_yad_smoke_reports_missing_tools_with_exit_status_2_before_doing_anything() {
    local _bin="$TEST_TEMP_DIR/smoke-bin" _tool _output _status=0

    mkdir -p "$_bin"
    for _tool in bash dirname env; do
        ln -sf "$(command -v "$_tool")" "$_bin/$_tool"
    done

    _output=$(env -i PATH="$_bin" HOME="$TEST_TEMP_DIR" "$_bin/bash" "$REPO_DIR/scripts/diagnostics/smoke_yad.sh" 2>&1) || _status=$?

    [[ $_status -eq 2 ]]
    [[ $_output == *"Missing required tools: yad Xvfb xdotool"* ]]
}

test_yad_smoke_workspace_holds_three_games_two_packs_and_a_stub_7z() {
    local _ws="$TEST_TEMP_DIR/yad-smoke-ws" _steamapps

    (
        source "$REPO_DIR/scripts/diagnostics/helpers/smoke_yad_common.sh"
        yadsmoke_workspace "$_ws"
    )
    _steamapps="$_ws/home/.local/share/Steam/steamapps"

    [[ $(find "$_steamapps" -maxdepth 1 -name 'appmanifest_*.acf' | wc -l) -eq 3 ]]
    grep -q 'Tom & Jerry <Demo>' "$_steamapps/appmanifest_1002.acf"
    [[ -f $_ws/reshade/ReShade_shaders/repo-a/Shaders/repo-a.fx && -f $_ws/reshade/ReShade_shaders/repo-b/Shaders/repo-b.fx ]]
    [[ -x $_ws/fake-bin/7z ]]
    [[ -f $_ws/reshade/reshade/latest/ReShade64.dll ]]
}

test_yad_smoke_lists_a_scenario_for_every_flow_the_checklists_mark_as_automated() {
    local _scenario

    for _scenario in install_with_defaults cancel_at_the_first_dialog cancel_at_the_game_picker \
        game_with_markup_characters_in_its_name unsupported_dll_name_is_rejected no_shader_packs_selected \
        failed_shader_download_offers_a_retry action_list_follows_the_highlighted_row \
        update_all_ends_with_a_confirmation fatal_errors_are_shown_in_a_dialog; do
        grep -q "^scenario_$_scenario()" "$REPO_DIR/scripts/diagnostics/smoke_yad.sh" || { echo "missing scenario $_scenario" >&2; return 1; }
        grep -q "^    $_scenario\$" "$REPO_DIR/scripts/diagnostics/smoke_yad.sh" || { echo "$_scenario is not in SCENARIOS" >&2; return 1; }
    done
}

run_gui_launch_tests() {
    echo -e "${BLUE}Graphical Launch Tests${NC}"
    run_test "Wrapper uses yad when installed" test_wrapper_uses_yad_when_it_is_installed
    run_test "Wrapper opens a terminal when yad is missing" test_wrapper_opens_a_terminal_when_yad_is_missing_and_launched_from_the_desktop
    run_test "Wrapper keeps the terminal open" test_wrapper_holds_the_terminal_open_so_the_result_can_be_read
    run_test "Wrapper uses each terminal's own run syntax" test_wrapper_uses_each_terminals_own_way_to_run_a_command_and_wait
    run_test "Wrapper does not nest terminals" test_wrapper_does_not_open_a_second_terminal_from_inside_one
    run_test "Wrapper ignores terminals without a display" test_wrapper_does_nothing_special_without_a_display
    run_test "Wrapper notifies when there is no terminal" test_wrapper_tells_the_desktop_user_when_there_is_no_terminal_either
    run_test "yad smoke exits 2 when tools are missing" test_yad_smoke_reports_missing_tools_with_exit_status_2_before_doing_anything
    run_test "yad smoke workspace is complete" test_yad_smoke_workspace_holds_three_games_two_packs_and_a_stub_7z
    run_test "yad smoke registers every scenario" test_yad_smoke_lists_a_scenario_for_every_flow_the_checklists_mark_as_automated
    run_test "Wrapper passes on the exit status and does not retry" test_wrapper_passes_on_the_installers_exit_status_and_does_not_start_it_again_elsewhere
    run_test "Wrapper moves on when a terminal cannot start" test_wrapper_moves_on_when_a_terminal_cannot_be_started
    run_test "yad smoke keeps its workspace when it fails" test_yad_smoke_keeps_its_workspace_and_reports_a_failing_exit_status
    run_test "yad smoke removes its workspace after a pass" test_yad_smoke_removes_its_workspace_after_a_passing_run
    run_test "yad smoke never kills unrelated yad windows" test_yad_smoke_never_kills_yad_windows_it_did_not_start
    run_test "yad smoke recognises progress windows by process" test_yad_smoke_recognises_a_progress_window_by_its_process
    run_test "Smoke failure report skips binary logs" test_smoke_failure_report_skips_binary_logs
    run_test "Wrapper reports the installer's status past an xterm-like emulator" test_wrapper_reports_the_installers_status_even_when_the_terminal_always_exits_zero
    run_test "Wrapper returns zero when the terminal run succeeds" test_wrapper_returns_zero_when_the_run_in_the_terminal_succeeds
    run_test "Wrapper never opens a terminal for a scripted run" test_wrapper_never_opens_a_terminal_for_a_scripted_run_with_arguments
    echo ""
}
