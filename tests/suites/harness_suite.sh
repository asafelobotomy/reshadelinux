#!/bin/bash
# Self-tests for the test runner itself.
#
# These exist because the runner once executed test bodies inside an `&&` chain,
# which disables `set -e` and let failed assertions in the middle of a test pass.
# Each "broken" function below fails on purpose; run_test_expect_fail only passes
# when the runner reports that failure.

# shellcheck disable=SC2317  # Test bodies are invoked indirectly by name.

harness_multi_assertion_test_passes() {
    local word="alpha" number=1
    [[ $word == "alpha" ]]
    [[ $number -eq 1 ]]
    [[ $word != "beta" ]]
}

harness_broken_first_of_many_assertions() {
    local word="alpha" number=1
    [[ $word == "beta" ]]
    [[ $number -eq 1 ]]
    [[ $word != "beta" ]]
}

harness_broken_middle_assertion() {
    local word="alpha" number=1
    [[ $word == "alpha" ]]
    [[ $number -eq 2 ]]
    [[ $word != "beta" ]]
}

harness_broken_bare_command_in_middle() {
    true
    false
    true
}

harness_broken_last_assertion() {
    local word="alpha"
    [[ $word == "alpha" ]]
    [[ $word == "beta" ]]
}

run_harness_tests() {
    echo -e "${BLUE}Harness Self-Tests${NC}"
    run_test "Passing multi-assertion test passes" harness_multi_assertion_test_passes
    run_test_expect_fail "First of several failing assertions is detected" harness_broken_first_of_many_assertions
    run_test_expect_fail "Failing assertion in the middle is detected" harness_broken_middle_assertion
    run_test_expect_fail "Failing bare command in the middle is detected" harness_broken_bare_command_in_middle
    run_test_expect_fail "Failing last assertion is detected" harness_broken_last_assertion
    echo ""
}
