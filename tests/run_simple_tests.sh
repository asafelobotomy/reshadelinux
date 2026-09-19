#!/bin/bash
# Simple bash-based test runner (doesn't require BATS installation)
# Tests core reshadelinux.sh detection functions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Source test utilities
# shellcheck source=./helpers/fixtures.sh
source "$SCRIPT_DIR/helpers/fixtures.sh" || {
    echo "Failed to source helpers/fixtures.sh"
    exit 1
}
# shellcheck source=./helpers/test_loader.sh
source "$SCRIPT_DIR/helpers/test_loader.sh" || {
    echo "Failed to source helpers/test_loader.sh"
    exit 1
}
# shellcheck source=./suites/harness_suite.sh
source "$SCRIPT_DIR/suites/harness_suite.sh" || {
    echo "Failed to source suites/harness_suite.sh"
    exit 1
}
# shellcheck source=./suites/exe_suite.sh
source "$SCRIPT_DIR/suites/exe_suite.sh" || {
    echo "Failed to source suites/exe_suite.sh"
    exit 1
}
# shellcheck source=./suites/detection_suite.sh
source "$SCRIPT_DIR/suites/detection_suite.sh" || {
    echo "Failed to source suites/detection_suite.sh"
    exit 1
}
# shellcheck source=./suites/state_suite.sh
source "$SCRIPT_DIR/suites/state_suite.sh" || {
    echo "Failed to source suites/state_suite.sh"
    exit 1
}
# shellcheck source=./suites/release_metadata_suite.sh
source "$SCRIPT_DIR/suites/release_metadata_suite.sh" || {
    echo "Failed to source suites/release_metadata_suite.sh"
    exit 1
}
# shellcheck source=./suites/shader_suite.sh
source "$SCRIPT_DIR/suites/shader_suite.sh" || {
    echo "Failed to source suites/shader_suite.sh"
    exit 1
}
# shellcheck source=./suites/flow_suite.sh
source "$SCRIPT_DIR/suites/flow_suite.sh" || {
    echo "Failed to source suites/flow_suite.sh"
    exit 1
}
# shellcheck source=./suites/deps_suite.sh
source "$SCRIPT_DIR/suites/deps_suite.sh" || {
    echo "Failed to source suites/deps_suite.sh"
    exit 1
}
# shellcheck source=./suites/install_suite.sh
source "$SCRIPT_DIR/suites/install_suite.sh" || {
    echo "Failed to source suites/install_suite.sh"
    exit 1
}
# shellcheck source=./suites/update_suite.sh
source "$SCRIPT_DIR/suites/update_suite.sh" || {
    echo "Failed to source suites/update_suite.sh"
    exit 1
}
# shellcheck source=./suites/repos_suite.sh
source "$SCRIPT_DIR/suites/repos_suite.sh" || {
    echo "Failed to source suites/repos_suite.sh"
    exit 1
}
# shellcheck source=./suites/ui_suite.sh
source "$SCRIPT_DIR/suites/ui_suite.sh" || {
    echo "Failed to source suites/ui_suite.sh"
    exit 1
}
# shellcheck source=./suites/pe_suite.sh
source "$SCRIPT_DIR/suites/pe_suite.sh" || {
    echo "Failed to source suites/pe_suite.sh"
    exit 1
}
# shellcheck source=./suites/release_suite.sh
source "$SCRIPT_DIR/suites/release_suite.sh" || {
    echo "Failed to source suites/release_suite.sh"
    exit 1
}
# shellcheck source=./suites/cli_suite.sh
source "$SCRIPT_DIR/suites/cli_suite.sh" || {
    echo "Failed to source suites/cli_suite.sh"
    exit 1
}

# Run one test function in an isolated environment and return its status.
#
# The test body must run under a real `set -e`. Bash ignores errexit for anything
# executed inside a condition context (`&&`, `||`, `if`, `!`), including a subshell
# or function called from one, so a failed assertion in the middle of a test would
# go unnoticed and only its final statement could fail it. Call this function as a
# plain statement, never as part of a condition.
_execute_test() {
    local test_func="$1"
    local rc=0 had_errexit=0

    [[ $- == *e* ]] && had_errexit=1

    if ! setup_test_env; then
        teardown_test_env 2>/dev/null || true
        return 1
    fi
    export BUILTIN_GAME_DIR_PRESETS="1091500|bin/x64;292030|bin/x64;275850|Binaries;1245620|Game;306130|The Elder Scrolls Online/game/client;2623190|OblivionRemastered/Binaries/Win64"

    set +e
    ( set -e; "$test_func" )
    rc=$?
    [[ $had_errexit -eq 1 ]] && set -e

    teardown_test_env 2>/dev/null || true
    return "$rc"
}

_record_test_result() {
    local passed="$1"
    local test_name="$2"

    if [[ $passed -eq 1 ]]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$(( TESTS_PASSED + 1 ))
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$(( TESTS_FAILED + 1 ))
        FAILED_TESTS+=("$test_name")
    fi
}

run_test() {
    local test_name="$1"
    local test_func="$2"
    local rc=0

    echo -n "  $test_name ... "
    TESTS_RUN=$(( TESTS_RUN + 1 ))

    set +e
    _execute_test "$test_func"
    rc=$?
    set -e

    if [[ $rc -eq 0 ]]; then
        _record_test_result 1 "$test_name"
    else
        _record_test_result 0 "$test_name"
    fi
}

# Passes only when the test function is detected as failing. Used by the harness
# self-tests to prove the runner cannot silently swallow a failed assertion.
run_test_expect_fail() {
    local test_name="$1"
    local test_func="$2"
    local rc=0

    echo -n "  $test_name ... "
    TESTS_RUN=$(( TESTS_RUN + 1 ))

    set +e
    _execute_test "$test_func" >/dev/null 2>&1
    rc=$?
    set -e

    if [[ $rc -ne 0 ]]; then
        _record_test_result 1 "$test_name"
    else
        _record_test_result 0 "$test_name (failure was not detected)"
    fi
}

main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}ReShadeLinux Test Suite${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    run_harness_tests
    run_exe_tests
    run_detection_tests
    run_state_tests
    run_release_metadata_tests
    run_shader_tests
    run_flow_tests
    run_deps_tests
    run_install_tests
    run_update_tests
    run_repo_sync_tests
    run_ui_tests
    run_pe_tests
    run_release_tests
    run_cli_tests

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}========================================${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All $TESTS_RUN tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ $TESTS_FAILED/$TESTS_RUN tests failed${NC}"
        echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
        echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
        if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
            echo -e "\n${RED}Failed tests:${NC}"
            local test
            for test in "${FAILED_TESTS[@]}"; do
                echo "  - $test"
            done
        fi
        return 1
    fi
}

main "$@"
