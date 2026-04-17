#!/bin/bash
# Simple bash-based test runner (doesn't require BATS installation)
# Tests core reshade-linux.sh detection functions

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
# shellcheck source=./suites/detection_suite.sh
source "$SCRIPT_DIR/suites/detection_suite.sh" || {
    echo "Failed to source suites/detection_suite.sh"
    exit 1
}
# shellcheck source=./suites/state_shader_suite.sh
source "$SCRIPT_DIR/suites/state_shader_suite.sh" || {
    echo "Failed to source suites/state_shader_suite.sh"
    exit 1
}
# shellcheck source=./suites/cli_suite.sh
source "$SCRIPT_DIR/suites/cli_suite.sh" || {
    echo "Failed to source suites/cli_suite.sh"
    exit 1
}

run_test() {
    local test_name="$1"
    local test_func="$2"

    echo -n "  $test_name ... "
    TESTS_RUN=$(( TESTS_RUN + 1 ))

    if setup_test_env && \
       export BUILTIN_GAME_DIR_PRESETS="1091500|bin/x64;292030|bin/x64;275850|Binaries;1245620|Game;306130|The Elder Scrolls Online/game/client;2623190|OblivionRemastered/Binaries/Win64" && \
       "$test_func" && \
       teardown_test_env; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$(( TESTS_PASSED + 1 ))
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$(( TESTS_FAILED + 1 ))
        FAILED_TESTS+=("$test_name")
        teardown_test_env 2>/dev/null || true
    fi
}

main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}ReShade Linux Test Suite${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    run_detection_tests
    run_state_and_shader_tests
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
