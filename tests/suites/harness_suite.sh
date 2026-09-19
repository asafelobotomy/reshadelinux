#!/bin/bash
# Self-tests for the test runner itself.
#
# These exist because the runner once executed test bodies inside an `&&` chain,
# which disables `set -e` and let failed assertions in the middle of a test pass.
# Each "broken" function below fails on purpose; run_test_expect_fail only passes
# when the runner reports that failure.

# shellcheck disable=SC2317,SC2329  # Test bodies are invoked indirectly by name.

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

harness_assert_fails_passes_when_the_command_fails() {
    assert_fails false
    assert_fails grep -q "needle" /dev/null
}

harness_assert_fails_treats_a_command_that_exits_the_shell_as_failing() {
    _exits_the_shell() { exit 1; }
    assert_fails _exits_the_shell
    [[ 1 -eq 1 ]]
}

harness_broken_assert_fails_on_a_command_that_succeeds() {
    assert_fails true
}

harness_broken_assert_fails_on_a_command_that_succeeds_mid_test() {
    assert_fails true
    local word="alpha"
    [[ $word == "alpha" ]]
}

test_test_suites_do_not_use_bare_negated_commands() {
    local _hits
    local -a _suites=("$REPO_DIR"/tests/suites/*.sh)

    # Guard against checking nothing: the suites must actually be found.
    [[ ${#_suites[@]} -ge 10 && -f ${_suites[0]} ]]

    # Bash exempts a negated command from errexit, so a bare "! cmd" in the middle of
    # a test never fails it. assert_fails is the supported way to expect a failure.
    _hits=$(grep -nE '^[[:space:]]+![[:space:]]+[^[[:space:]]' "${_suites[@]}" || true)
    if [[ -n $_hits ]]; then
        printf 'use assert_fails instead of a bare negated command:\n%s\n' "$_hits" >&2
        return 1
    fi
}

run_harness_tests() {
    echo -e "${BLUE}Harness Self-Tests${NC}"
    run_test "Passing multi-assertion test passes" harness_multi_assertion_test_passes
    run_test_expect_fail "First of several failing assertions is detected" harness_broken_first_of_many_assertions
    run_test_expect_fail "Failing assertion in the middle is detected" harness_broken_middle_assertion
    run_test_expect_fail "Failing bare command in the middle is detected" harness_broken_bare_command_in_middle
    run_test_expect_fail "Failing last assertion is detected" harness_broken_last_assertion
    run_test "assert_fails passes when the command fails" harness_assert_fails_passes_when_the_command_fails
    run_test "assert_fails counts an exiting command as failing" harness_assert_fails_treats_a_command_that_exits_the_shell_as_failing
    run_test_expect_fail "assert_fails detects a succeeding command" harness_broken_assert_fails_on_a_command_that_succeeds
    run_test_expect_fail "assert_fails detects a succeeding command mid-test" harness_broken_assert_fails_on_a_command_that_succeeds_mid_test
    run_test "Test suites avoid bare negated commands" test_test_suites_do_not_use_bare_negated_commands
    echo ""
}
