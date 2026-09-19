#!/bin/bash

# The version is recorded in five places; scripts/release/check-version-sync.sh
# verifies they agree, and the release tool runs it before building.

_VERSION_CHECK="$REPO_DIR/scripts/release/check-version-sync.sh"
_METAINFO_PATH="packaging/appimage/AppDir/io.github.asafelobotomy.reshadelinux.metainfo.xml"
_DESKTOP_PATH="packaging/appimage/AppDir/io.github.asafelobotomy.reshadelinux.desktop"

# Copy the five version-bearing files into a scratch tree and print its path.
_copy_release_files() {
    local _dest="$TEST_TEMP_DIR/release-copy-$RANDOM" _file

    for _file in VERSION CHANGELOG.md reshadelinux.sh "$_METAINFO_PATH" "$_DESKTOP_PATH"; do
        mkdir -p "$_dest/$(dirname "$_file")"
        cp "$REPO_DIR/$_file" "$_dest/$_file"
    done
    printf '%s\n' "$_dest"
}

# Run the check on a tree, returning its status and leaving its output in _check_output.
_run_version_check() {
    local _status=0

    set +e
    _check_output=$("$_VERSION_CHECK" "$1" 2>&1)
    _status=$?
    set -e
    return "$_status"
}

test_repository_versions_are_in_sync() {
    "$_VERSION_CHECK" "$REPO_DIR" >/dev/null
}

test_version_check_rejects_a_changelog_that_does_not_match_version() {
    local _tree _check_output

    _tree=$(_copy_release_files)
    sed -i '0,/^## \[[0-9][^]]*\]/s//## [9.9.9]/' "$_tree/CHANGELOG.md"

    assert_fails _run_version_check "$_tree"
    _run_version_check "$_tree" || true
    [[ $_check_output == *"CHANGELOG.md"* ]]
}

test_version_check_rejects_an_undated_changelog_release() {
    local _tree _check_output

    _tree=$(_copy_release_files)
    sed -i '0,/^## \[[0-9][^]]*\] - .*/s//## [1.3.1]/' "$_tree/CHANGELOG.md"

    _run_version_check "$_tree" || true
    [[ $_check_output == *"no ISO date"* ]]
}

test_version_check_rejects_a_stale_metainfo_release() {
    local _tree _check_output

    _tree=$(_copy_release_files)
    sed -i '0,/<release version="[^"]*"/s//<release version="0.0.1"/' "$_tree/$_METAINFO_PATH"

    assert_fails _run_version_check "$_tree"
    _run_version_check "$_tree" || true
    [[ $_check_output == *"metainfo"* ]]
}

test_version_check_rejects_a_stale_script_fallback() {
    local _tree _check_output

    _tree=$(_copy_release_files)
    sed -i "s/printf '[0-9][^']*'/printf '0.0.1'/" "$_tree/reshadelinux.sh"

    assert_fails _run_version_check "$_tree"
    _run_version_check "$_tree" || true
    [[ $_check_output == *"reshadelinux.sh"* ]]
}

test_version_check_rejects_a_stale_desktop_entry() {
    local _tree _check_output

    _tree=$(_copy_release_files)
    sed -i 's/^X-AppImage-Version=.*/X-AppImage-Version=0.0.1/' "$_tree/$_DESKTOP_PATH"

    assert_fails _run_version_check "$_tree"
    _run_version_check "$_tree" || true
    [[ $_check_output == *"desktop"* ]]
}

test_version_check_rejects_a_version_that_is_not_major_minor_patch() {
    local _tree _check_output

    _tree=$(_copy_release_files)
    printf '1.3\n' > "$_tree/VERSION"

    _run_version_check "$_tree" || true
    [[ $_check_output == *"MAJOR.MINOR.PATCH"* ]]
}

test_version_check_reports_every_mismatch_not_just_the_first() {
    local _tree _check_output

    _tree=$(_copy_release_files)
    sed -i "s/printf '[0-9][^']*'/printf '0.0.1'/" "$_tree/reshadelinux.sh"
    sed -i 's/^X-AppImage-Version=.*/X-AppImage-Version=0.0.1/' "$_tree/$_DESKTOP_PATH"

    _run_version_check "$_tree" || true
    [[ $_check_output == *"reshadelinux.sh"* && $_check_output == *"desktop"* ]]
}

test_version_check_allows_an_unreleased_section_above_the_current_release() {
    local _tree _check_output

    _tree=$(_copy_release_files)
    {
        printf '## [Unreleased]\n\n### Added\n\n- Something not released yet.\n\n'
        sed -n '/^## \[[0-9]/,$p' "$_tree/CHANGELOG.md"
    } > "$_tree/CHANGELOG.new"
    mv "$_tree/CHANGELOG.new" "$_tree/CHANGELOG.md"

    _run_version_check "$_tree"
}

test_shipped_shell_files_declare_their_license() {
    local _file _missing=""

    for _file in "$REPO_DIR"/reshadelinux.sh "$REPO_DIR"/reshadelinux-gui.sh "$REPO_DIR"/lib/*.sh; do
        grep -q '^# SPDX-License-Identifier: GPL-2.0-or-later$' "$_file" || _missing+=" ${_file#"$REPO_DIR"/}"
    done
    [[ -z $_missing ]] || { echo "missing SPDX identifier:$_missing" >&2; return 1; }
}

test_the_entrypoint_keeps_its_license_notice_as_comments_not_heredocs() {
    grep -q 'Copyright (C) 2021-2022  kevinlekiller' "$REPO_DIR/reshadelinux.sh"
    assert_fails grep -q '^cat > /dev/null' "$REPO_DIR/reshadelinux.sh"
}

run_release_metadata_tests() {
    echo -e "${BLUE}Release Metadata Tests${NC}"
    run_test "Repository versions are in sync" test_repository_versions_are_in_sync
    run_test "Rejects a changelog that differs from VERSION" test_version_check_rejects_a_changelog_that_does_not_match_version
    run_test "Rejects an undated changelog release" test_version_check_rejects_an_undated_changelog_release
    run_test "Rejects a stale metainfo release" test_version_check_rejects_a_stale_metainfo_release
    run_test "Rejects a stale script fallback version" test_version_check_rejects_a_stale_script_fallback
    run_test "Rejects a stale desktop entry version" test_version_check_rejects_a_stale_desktop_entry
    run_test "Rejects a version that is not MAJOR.MINOR.PATCH" test_version_check_rejects_a_version_that_is_not_major_minor_patch
    run_test "Reports every mismatch" test_version_check_reports_every_mismatch_not_just_the_first
    run_test "Allows an Unreleased section above the release" test_version_check_allows_an_unreleased_section_above_the_current_release
    run_test "Shipped shell files declare their license" test_shipped_shell_files_declare_their_license
    run_test "Entrypoint keeps its license notice as comments" test_the_entrypoint_keeps_its_license_notice_as_comments_not_heredocs
    echo ""
}
