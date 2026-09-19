#!/bin/bash
# shellcheck disable=SC2030,SC2031  # the helper is exercised inside subshells on purpose

# Smoke runners must never throw away the evidence of a failure.

_run_smoke_finish() {
    local _root="$1" _status="$2"

    (
        source "$REPO_DIR/scripts/diagnostics/helpers/smoke_common.sh"
        # shellcheck disable=SC2064  # expand the workspace path now, when the trap is set
        trap "smoke_finish '$_root'" EXIT
        exit "$_status"
    ) 2>&1
}

_make_smoke_workspace() {
    local _root="$1"

    mkdir -p "$_root/case"
    printf 'first line\nsecond line explaining the failure\n' > "$_root/case/interactive-install.log"
}

test_smoke_workspace_is_removed_after_a_passing_run() {
    local _root="$TEST_TEMP_DIR/smoke-pass"

    _make_smoke_workspace "$_root"
    _run_smoke_finish "$_root" 0 >/dev/null
    [[ ! -e $_root ]]
}

test_smoke_workspace_and_log_tails_survive_a_failing_run() {
    local _root="$TEST_TEMP_DIR/smoke-fail" _output

    _make_smoke_workspace "$_root"
    _output=$(_run_smoke_finish "$_root" 3) || true

    [[ -d $_root/case ]]
    [[ $_output == *"SMOKE_RESULT=FAIL"* ]]
    [[ $_output == *"second line explaining the failure"* ]]
    [[ $_output == *"$_root"* ]]
}

test_smoke_workspace_is_kept_when_asked_even_after_a_passing_run() {
    local _root="$TEST_TEMP_DIR/smoke-keep"

    _make_smoke_workspace "$_root"
    SMOKE_KEEP_WORKSPACE=1 _run_smoke_finish "$_root" 0 >/dev/null
    [[ -d $_root/case ]]
}

test_smoke_wrappers_that_only_repeated_other_entry_points_are_gone() {
    local _script

    for _script in smoke_cli_no_cleanup.sh smoke_cli_no_trap.sh test_dialog.sh; do
        [[ ! -e $REPO_DIR/scripts/diagnostics/$_script ]] || { echo "$_script still exists" >&2; return 1; }
    done
}

run_diagnostics_tests() {
    echo -e "${BLUE}Diagnostics Tests${NC}"
    run_test "Smoke workspace is removed after a pass" test_smoke_workspace_is_removed_after_a_passing_run
    run_test "Smoke workspace and log tails survive a failure" test_smoke_workspace_and_log_tails_survive_a_failing_run
    run_test "Smoke workspace can be kept on request" test_smoke_workspace_is_kept_when_asked_even_after_a_passing_run
    run_test "Redundant smoke wrappers are gone" test_smoke_wrappers_that_only_repeated_other_entry_points_are_gone
    echo ""
}
