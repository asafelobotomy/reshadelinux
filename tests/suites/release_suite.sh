#!/bin/bash
# shellcheck disable=SC2317,SC2329  # test functions and stubs are invoked indirectly
# shellcheck disable=SC2034  # stubs assign variables that the sourced release script reads
# shellcheck disable=SC2030,SC2031  # the release script is sourced inside subshells on purpose

# Release tooling: helper functions in scripts/release/lib-release.sh.

# shellcheck source=../../scripts/release/lib-release.sh
source "$REPO_DIR/scripts/release/lib-release.sh"

# Create a git repository on "main" holding every release file plus one unrelated file.
_make_release_repo() {
    local _dir="$1" _file

    mkdir -p "$_dir"
    git init -q -b main "$_dir"
    for _file in "${RELEASE_FILES[@]}" other.txt; do
        mkdir -p "$_dir/$(dirname "$_file")"
        printf 'initial\n' > "$_dir/$_file"
    done
    git -C "$_dir" add -A
    _commit_release_repo "$_dir" "initial"
}

_commit_release_repo() {
    GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid \
        GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid \
        git -C "$1" commit -q -m "$2"
}

test_appimagetool_hash_accepts_the_pinned_file_in_either_case() {
    local _file="$TEST_TEMP_DIR/tool" _pin="$TEST_TEMP_DIR/tool.sha256" _hash _rest

    printf 'binary\n' > "$_file"
    read -r _hash _rest < <(sha256sum "$_file")
    printf '%s  tool\n' "$_hash" > "$_pin"
    ( verify_appimagetool_hash "$_file" "$_pin" )

    printf '%s  tool\n' "${_hash^^}" > "$_pin"
    ( verify_appimagetool_hash "$_file" "$_pin" )
}

test_appimagetool_hash_rejects_a_file_that_does_not_match() {
    local _file="$TEST_TEMP_DIR/tool" _pin="$TEST_TEMP_DIR/tool.sha256" _output

    printf 'binary\n' > "$_file"
    printf '%s  tool\n' "$(printf '0%.0s' {1..64})" > "$_pin"

    assert_fails verify_appimagetool_hash "$_file" "$_pin"
    _output=$( ( verify_appimagetool_hash "$_file" "$_pin" ) 2>&1 || true )
    [[ $_output == *"checksum mismatch"* ]]
}

test_appimagetool_hash_rejects_a_missing_or_malformed_pin() {
    local _file="$TEST_TEMP_DIR/tool" _pin="$TEST_TEMP_DIR/tool.sha256"

    printf 'binary\n' > "$_file"
    assert_fails verify_appimagetool_hash "$_file" "$_pin"

    printf 'not-a-hash  tool\n' > "$_pin"
    assert_fails verify_appimagetool_hash "$_file" "$_pin"

    printf '*  tool\n' > "$_pin"
    assert_fails verify_appimagetool_hash "$_file" "$_pin"
}

test_the_committed_appimagetool_pin_is_a_well_formed_sha256() {
    local _hash _name

    read -r _hash _name < "$REPO_DIR/packaging/appimagetool.sha256"
    [[ $_hash =~ ^[0-9a-f]{64}$ ]]
    [[ $_name == "$APPIMAGETOOL_ASSET" ]]
}

_write_sample_changelog() {
    cat > "$1" <<'CHANGELOG'
# Changelog

## [Unreleased]

- Next thing.

## [1.3.1] - 2026-04-17

### Fixed

- The fix.

## [1x3x1] - 2020-01-01

- Wildcard bait.

## [1.3.0] - 2026-03-17

- Older change.
CHANGELOG
}

test_release_notes_contain_only_the_requested_version() {
    local _file="$TEST_TEMP_DIR/CHANGELOG.md" _notes

    _write_sample_changelog "$_file"
    _notes=$(extract_release_notes "1.3.1" "$_file")

    [[ $_notes == *"The fix."* ]]
    [[ $_notes != *"Next thing."* && $_notes != *"Older change."* && $_notes != *"Wildcard bait."* ]]
}

test_release_notes_treat_the_version_literally_and_are_empty_when_unknown() {
    local _file="$TEST_TEMP_DIR/CHANGELOG.md"

    _write_sample_changelog "$_file"
    [[ -z $(extract_release_notes "9.9.9" "$_file") ]]
    [[ -z $(extract_release_notes "1.3.x" "$_file") ]]
}

test_release_branch_check_accepts_main_and_rejects_other_branches() {
    local _repo="$TEST_TEMP_DIR/release-branch"

    _make_release_repo "$_repo"
    ( ensure_release_branch "$_repo" )

    git -C "$_repo" checkout -q -b feature
    assert_fails ensure_release_branch "$_repo"
}

test_only_release_files_may_carry_uncommitted_changes() {
    local _repo="$TEST_TEMP_DIR/release-changes" _output

    _make_release_repo "$_repo"
    ( ensure_only_release_files_changed "$_repo" )

    printf 'bumped\n' > "$_repo/VERSION"
    printf 'notes\n' > "$_repo/CHANGELOG.md"
    ( ensure_only_release_files_changed "$_repo" )

    printf 'sneaky\n' > "$_repo/other.txt"
    assert_fails ensure_only_release_files_changed "$_repo"
    _output=$( ( ensure_only_release_files_changed "$_repo" ) 2>&1 || true )
    [[ $_output == *"other.txt"* && $_output != *"VERSION"* ]]
}

test_untracked_files_block_a_release() {
    local _repo="$TEST_TEMP_DIR/release-untracked"

    _make_release_repo "$_repo"
    ( ensure_no_untracked_files "$_repo" )

    printf 'stray\n' > "$_repo/stray.txt"
    assert_fails ensure_no_untracked_files "$_repo"
}

test_release_tag_is_created_reused_at_head_and_refused_elsewhere() {
    local _repo="$TEST_TEMP_DIR/release-tag"

    _make_release_repo "$_repo"
    export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

    ensure_release_tag "$_repo" v1.0.0
    [[ $(git -C "$_repo" rev-list -n 1 v1.0.0) == "$(git -C "$_repo" rev-parse HEAD)" ]]
    ensure_release_tag "$_repo" v1.0.0

    printf 'more\n' >> "$_repo/other.txt"
    git -C "$_repo" add -A
    _commit_release_repo "$_repo" "second"
    assert_fails ensure_release_tag "$_repo" v1.0.0
}

# Run the release tool's main() with every phase that touches the network, git or the
# build replaced by a recorder. Phases append their name to $1; extra arguments go to main.
# _STUB_PRECONDITIONS=fail makes the precondition check end the run; _STUB_ANSWER feeds
# the confirmation prompt; _STUB_REPO_ROOT overrides the repository used.
_run_release_main_with_stubs() {
    local _log="$1"
    shift

    (
        source "$REPO_DIR/scripts/release/release-appimage.sh"
        require_command() { :; }
        run_validation() { echo validation >> "$_log"; }
        prepare_appimagetool() { echo prepare-tool >> "$_log"; APPIMAGETOOL_BIN=/bin/true; }
        build_appimage() { echo build >> "$_log"; }
        validate_artifact() { echo validate-artifact >> "$_log"; }
        ensure_release_preconditions() {
            echo preconditions >> "$_log"
            if [[ ${_STUB_PRECONDITIONS:-ok} == fail ]]; then print_err "not on main"; fi
        }
        commit_release_changes() { echo commit >> "$_log"; }
        ensure_release_tag() { echo tag >> "$_log"; }
        push_release() { echo push >> "$_log"; }
        publish_release() { echo publish >> "$_log"; }
        main "$@" --repo-root "${_STUB_REPO_ROOT:-$REPO_DIR}" <<< "${_STUB_ANSWER:-}"
    ) >/dev/null 2>&1
}

_logged_phases() {
    [[ -f $1 ]] && tr '\n' ' ' < "$1" | sed 's/ $//'
    return 0
}

test_build_only_never_commits_tags_pushes_or_publishes() {
    local _log="$TEST_TEMP_DIR/phases.log"

    _run_release_main_with_stubs "$_log" --build-only
    [[ $(_logged_phases "$_log") == "validation prepare-tool build validate-artifact" ]]
}

test_a_full_release_runs_every_phase_in_order() {
    local _log="$TEST_TEMP_DIR/phases.log"

    _run_release_main_with_stubs "$_log" --yes
    [[ $(_logged_phases "$_log") == "preconditions validation prepare-tool build validate-artifact commit tag push publish" ]]
}

test_skip_release_still_pushes_but_does_not_publish() {
    local _log="$TEST_TEMP_DIR/phases.log"

    _run_release_main_with_stubs "$_log" --yes --skip-release
    [[ $(_logged_phases "$_log") == "preconditions validation prepare-tool build validate-artifact commit tag push" ]]
}

test_a_failed_precondition_stops_before_any_build_or_git_change() {
    local _log="$TEST_TEMP_DIR/phases.log"

    export _STUB_PRECONDITIONS=fail
    assert_fails _run_release_main_with_stubs "$_log" --yes
    [[ $(_logged_phases "$_log") == "preconditions" ]]
}

test_declining_the_confirmation_prompt_changes_nothing() {
    local _log="$TEST_TEMP_DIR/phases.log"

    export _STUB_ANSWER=n
    assert_fails _run_release_main_with_stubs "$_log"
    [[ -z $(_logged_phases "$_log") ]]
}

test_inconsistent_version_files_block_every_mode() {
    local _log="$TEST_TEMP_DIR/phases.log" _tree="$TEST_TEMP_DIR/mismatched-release" _file

    for _file in VERSION CHANGELOG.md reshadelinux.sh scripts/release/check-version-sync.sh "${RELEASE_FILES[@]:3}"; do
        mkdir -p "$_tree/$(dirname "$_file")"
        cp "$REPO_DIR/$_file" "$_tree/$_file"
    done
    printf '9.9.9\n' > "$_tree/VERSION"

    export _STUB_REPO_ROOT="$_tree"
    assert_fails _run_release_main_with_stubs "$_log" --build-only
    assert_fails _run_release_main_with_stubs "$_log" --yes
    [[ -z $(_logged_phases "$_log") ]]
}

test_unknown_arguments_are_rejected() {
    local _log="$TEST_TEMP_DIR/phases.log"

    assert_fails _run_release_main_with_stubs "$_log" --push-everything
    [[ -z $(_logged_phases "$_log") ]]
}

run_release_tests() {
    echo -e "${BLUE}Release Tooling Tests${NC}"
    run_test "appimagetool hash accepts the pinned file" test_appimagetool_hash_accepts_the_pinned_file_in_either_case
    run_test "appimagetool hash rejects a different file" test_appimagetool_hash_rejects_a_file_that_does_not_match
    run_test "appimagetool hash rejects a missing or malformed pin" test_appimagetool_hash_rejects_a_missing_or_malformed_pin
    run_test "Committed appimagetool pin is well formed" test_the_committed_appimagetool_pin_is_a_well_formed_sha256
    run_test "Release notes hold only the requested version" test_release_notes_contain_only_the_requested_version
    run_test "Release notes match the version literally" test_release_notes_treat_the_version_literally_and_are_empty_when_unknown
    run_test "Release branch check" test_release_branch_check_accepts_main_and_rejects_other_branches
    run_test "Only release files may carry changes" test_only_release_files_may_carry_uncommitted_changes
    run_test "Untracked files block a release" test_untracked_files_block_a_release
    run_test "Release tag creation and reuse" test_release_tag_is_created_reused_at_head_and_refused_elsewhere
    run_test "--build-only never commits, tags, pushes or publishes" test_build_only_never_commits_tags_pushes_or_publishes
    run_test "A full release runs every phase in order" test_a_full_release_runs_every_phase_in_order
    run_test "--skip-release pushes but does not publish" test_skip_release_still_pushes_but_does_not_publish
    run_test "A failed precondition stops before any change" test_a_failed_precondition_stops_before_any_build_or_git_change
    run_test "Declining the prompt changes nothing" test_declining_the_confirmation_prompt_changes_nothing
    run_test "Inconsistent version files block every mode" test_inconsistent_version_files_block_every_mode
    run_test "Unknown arguments are rejected" test_unknown_arguments_are_rejected
    echo ""
}
