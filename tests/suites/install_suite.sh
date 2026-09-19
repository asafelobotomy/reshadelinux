#!/bin/bash

# Download verification and installation into a game directory.

test_hash_pin_rejects_glob_patterns_instead_of_matching_them() {
    local _file="$TEST_TEMP_DIR/payload.bin" _pin _rc

    printf 'hello\n' > "$_file"
    for _pin in '*' '?' '[0-9a-f]*' '*abc' '[!x]*'; do
        set +e
        ( use_fatal_printErr; RESHADE_SETUP_SHA256="$_pin" verifyReshadeDownloadHash "$_file" ) >/dev/null 2>&1
        _rc=$?
        set -e
        if [[ $_rc -eq 0 ]]; then
            echo "pin '$_pin' was accepted for a file it cannot match" >&2
            return 1
        fi
    done
}

test_hash_pin_rejects_a_well_formed_hash_that_does_not_match() {
    local _file="$TEST_TEMP_DIR/payload.bin" _pin _rc

    printf 'hello\n' > "$_file"
    _pin=$(printf '0%.0s' {1..64})

    set +e
    ( use_fatal_printErr; RESHADE_SETUP_SHA256="$_pin" verifyReshadeDownloadHash "$_file" ) >/dev/null 2>&1
    _rc=$?
    set -e

    [[ $_rc -ne 0 ]]
}

test_hash_pin_accepts_the_correct_hash_in_either_case() {
    local _file="$TEST_TEMP_DIR/payload.bin" _hash _rest

    printf 'hello\n' > "$_file"
    read -r _hash _rest < <(sha256sum "$_file")

    ( use_fatal_printErr; RESHADE_SETUP_SHA256="$_hash" verifyReshadeDownloadHash "$_file" ) >/dev/null 2>&1
    ( use_fatal_printErr; RESHADE_SETUP_SHA256="${_hash^^}" verifyReshadeDownloadHash "$_file" ) >/dev/null 2>&1
}

test_hash_pin_names_the_variable_when_the_value_is_malformed() {
    local _file="$TEST_TEMP_DIR/payload.bin" _output

    printf 'hello\n' > "$_file"
    _output=$( ( use_fatal_printErr; RESHADE_SETUP_SHA256='not-a-hash' verifyReshadeDownloadHash "$_file" ) 2>&1 || true )

    [[ $_output == *"RESHADE_SETUP_SHA256"* ]]
    [[ $_output == *"64"* ]]
}

test_hash_pin_is_skipped_when_unset() {
    local _file="$TEST_TEMP_DIR/payload.bin"

    printf 'hello\n' > "$_file"
    ( unset RESHADE_SETUP_SHA256; verifyReshadeDownloadHash "$_file" )
}

run_install_tests() {
    echo -e "${BLUE}Install and Verification Tests${NC}"
    run_test "Hash pin rejects glob patterns" test_hash_pin_rejects_glob_patterns_instead_of_matching_them
    run_test "Hash pin rejects a non-matching hash" test_hash_pin_rejects_a_well_formed_hash_that_does_not_match
    run_test "Hash pin accepts the correct hash" test_hash_pin_accepts_the_correct_hash_in_either_case
    run_test "Hash pin names the variable when malformed" test_hash_pin_names_the_variable_when_the_value_is_malformed
    run_test "Hash pin is skipped when unset" test_hash_pin_is_skipped_when_unset
    echo ""
}
