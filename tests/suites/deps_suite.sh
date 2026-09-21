#!/bin/bash
# shellcheck disable=SC2030,SC2031  # PATH and other settings are changed inside subshells on purpose

# Required-executable reporting: every missing tool is listed, package names are
# correct for the detected package manager, and GUI users get a dialog.

# Build a directory that holds only the named stub programs. Tests run the code under
# test with PATH pointing at it: builtins keep working, and any tool that is not
# stubbed is reliably "missing" whatever is installed on the host.
_make_stub_path() {
    local _dir="$TEST_TEMP_DIR/stub-bin" _name

    mkdir -p "$_dir"
    for _name in "$@"; do
        printf '#!/bin/sh\nexit 0\n' > "$_dir/$_name"
        chmod +x "$_dir/$_name"
    done
    printf '%s\n' "$_dir"
}

# Run checkRequiredExecutables in a subshell with the CLI backend and a
# process-terminating printErr. Prints combined output; returns its exit status.
_run_dependency_check() {
    local _stub="$1"
    shift

    (
        PATH="$_stub"
        _UI_BACKEND=cli
        use_fatal_printErr
        checkRequiredExecutables "$@"
    ) 2>&1
}

test_deps_lists_every_missing_tool_with_pacman_package_names() {
    local _stub _output _rc

    _stub=$(_make_stub_path pacman)
    set +e
    _output=$(_run_dependency_check "$_stub" 7z python3 sed)
    _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
    [[ $_output == *"7z"* && $_output == *"python3"* && $_output == *"sed"* ]]
    [[ $_output == *"sudo pacman -S 7zip python sed"* ]]
    [[ $_output != *"p7zip-full"* ]]
}

test_deps_uses_debian_package_names_for_apt() {
    local _stub _output _rc

    _stub=$(_make_stub_path apt-get)
    set +e
    _output=$(_run_dependency_check "$_stub" 7z git)
    _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
    [[ $_output == *"sudo apt-get install p7zip-full git"* ]]
}

test_deps_suggests_a_package_search_when_the_name_is_not_known_for_dnf() {
    local _stub _output _rc

    _stub=$(_make_stub_path dnf)
    set +e
    _output=$(_run_dependency_check "$_stub" 7z python3)
    _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
    [[ $_output == *"sudo dnf install python3"* ]]
    [[ $_output == *"dnf provides '*/bin/7z'"* ]]
    [[ $_output != *"p7zip-full"* ]]
}

test_deps_still_fails_with_a_clear_message_when_no_package_manager_is_found() {
    local _stub _output _rc

    _stub=$(_make_stub_path)
    set +e
    _output=$(_run_dependency_check "$_stub" 7z)
    _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
    [[ $_output == *"7z"* ]]
    [[ $_output != *"Install with"* ]]
}

test_deps_writes_the_report_to_stderr_not_stdout() {
    local _stub _stdout

    _stub=$(_make_stub_path pacman)
    _stdout=$( (
        PATH="$_stub"
        _UI_BACKEND=cli
        use_fatal_printErr
        checkRequiredExecutables 7z
    ) 2>/dev/null || true )

    [[ -z $_stdout ]]
}

test_deps_shows_an_error_dialog_for_the_yad_backend() {
    local _stub _log="$TEST_TEMP_DIR/yad.log" _rc

    _stub=$(_make_stub_path pacman)
    # The dialog wrapper needs working mktemp and rm; the stub directory is otherwise all fakes.
    ln -sf "$(command -v mktemp)" "$_stub/mktemp"
    ln -sf "$(command -v rm)" "$_stub/rm"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$_log" > "$_stub/yad"
    chmod +x "$_stub/yad"

    set +e
    (
        source "$REPO_DIR/lib/logging.sh"
        source "$REPO_DIR/lib/ui.sh"
        PATH="$_stub"
        _UI_BACKEND=yad
        checkRequiredExecutables 7z
    ) >/dev/null 2>&1
    _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
    [[ -f $_log ]]
    grep -q -- '--image=dialog-error' "$_log"
    grep -q '7z' "$_log"
}

test_deps_is_silent_and_succeeds_when_everything_is_present() {
    local _stub _output

    _stub=$(_make_stub_path git curl)
    _output=$(_run_dependency_check "$_stub" git curl)

    [[ -z $_output ]]
}

run_deps_tests() {
    echo -e "${BLUE}Dependency Reporting Tests${NC}"
    run_test "Lists every missing tool with pacman names" test_deps_lists_every_missing_tool_with_pacman_package_names
    run_test "Uses Debian package names for apt" test_deps_uses_debian_package_names_for_apt
    run_test "Suggests a package search for unknown dnf names" test_deps_suggests_a_package_search_when_the_name_is_not_known_for_dnf
    run_test "Fails clearly without a package manager" test_deps_still_fails_with_a_clear_message_when_no_package_manager_is_found
    run_test "Report goes to stderr not stdout" test_deps_writes_the_report_to_stderr_not_stdout
    run_test "Shows an error dialog for the yad backend" test_deps_shows_an_error_dialog_for_the_yad_backend
    run_test "Silent when every tool is present" test_deps_is_silent_and_succeeds_when_everything_is_present
    echo ""
}
