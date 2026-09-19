#!/bin/bash
# shellcheck disable=SC2317,SC2329  # test functions and stubs are invoked indirectly
# shellcheck disable=SC2034  # variables are set for the code under test

# ReShade version updates: the "latest" link must stay valid across failures and be
# repaired when it is lost.

# Stub the network and download layers for ensureRequestedReshadeVersion.
# $1 = file that records each downloadReshade call
# $2 = version the fake reshade.me advertises
# $3 = "fail" makes the download end the process like printErr does
_stub_reshade_update_environment() {
    local _remote="$2"

    _STUB_DOWNLOAD_CALLS="$1"
    _STUB_DOWNLOAD_MODE="${3:-ok}"

    export RESHADE_VERSION=latest
    export FORCE_RESHADE_UPDATE_CHECK=1
    init_test_runtime_defaults
    UPDATE_RESHADE=1
    RESHADE_URL="https://reshade.example.invalid"
    RESHADE_URL_ALT="https://reshade-alt.example.invalid"
    _CURL_PROG=(--silent)
    use_fatal_printErr

    eval "curl() { printf '<a href=\"/downloads/ReShade_Setup_${_remote}.exe\">download</a>'; }"
    withProgress() { shift; "$@"; }
    downloadReshade() {
        printf '%s\n' "$1" >> "$_STUB_DOWNLOAD_CALLS"
        if [[ $_STUB_DOWNLOAD_MODE == fail ]]; then
            printErr "simulated download failure"
        fi
        mkdir -p "$RESHADE_PATH/$1"
        touch "$RESHADE_PATH/$1/ReShade64.dll" "$RESHADE_PATH/$1/ReShade32.dll"
    }
}

_seed_reshade_version() {
    local _version="$1"

    mkdir -p "$RESHADE_PATH/$_version"
    touch "$RESHADE_PATH/$_version/ReShade64.dll" "$RESHADE_PATH/$_version/ReShade32.dll"
    printf '%s\n' "$_version" > "$MAIN_PATH/LVERS"
}

test_reshade_update_repairs_a_missing_latest_link_without_downloading() {
    local _calls="$TEST_TEMP_DIR/download.calls"

    _seed_reshade_version 9.9.9
    (
        set +e
        _stub_reshade_update_environment "$_calls" 9.9.9
        ensureRequestedReshadeVersion
    ) >/dev/null 2>&1

    [[ -L "$RESHADE_PATH/latest" ]]
    [[ $(readlink "$RESHADE_PATH/latest") == *"/9.9.9" ]]
    [[ -e "$RESHADE_PATH/latest/ReShade64.dll" ]]
    [[ ! -s $_calls ]]
}

test_reshade_update_keeps_the_previous_latest_link_when_the_download_fails() {
    local _calls="$TEST_TEMP_DIR/download.calls"

    _seed_reshade_version 1.0.0
    ln -sfn "$(realpath "$RESHADE_PATH/1.0.0")" "$RESHADE_PATH/latest"
    (
        set +e
        _stub_reshade_update_environment "$_calls" 9.9.9 fail
        ensureRequestedReshadeVersion
    ) >/dev/null 2>&1 || true

    [[ -s $_calls ]]
    [[ -L "$RESHADE_PATH/latest" ]]
    [[ $(readlink "$RESHADE_PATH/latest") == *"/1.0.0" ]]
    [[ -e "$RESHADE_PATH/latest/ReShade64.dll" ]]
}

test_reshade_update_downloads_again_when_the_recorded_version_is_missing_on_disk() {
    local _calls="$TEST_TEMP_DIR/download.calls"

    printf '9.9.9\n' > "$MAIN_PATH/LVERS"
    ln -sfn "$RESHADE_PATH/9.9.9" "$RESHADE_PATH/latest"
    (
        set +e
        _stub_reshade_update_environment "$_calls" 9.9.9
        ensureRequestedReshadeVersion
    ) >/dev/null 2>&1

    [[ $(<"$_calls") == "9.9.9" ]]
    [[ -e "$RESHADE_PATH/latest/ReShade64.dll" ]]
}

run_update_tests() {
    echo -e "${BLUE}ReShade Update Tests${NC}"
    run_test "Repairs a missing latest link without downloading" test_reshade_update_repairs_a_missing_latest_link_without_downloading
    run_test "Keeps the previous latest link when a download fails" test_reshade_update_keeps_the_previous_latest_link_when_the_download_fails
    run_test "Downloads again when the recorded version is gone" test_reshade_update_downloads_again_when_the_recorded_version_is_missing_on_disk
    echo ""
}
