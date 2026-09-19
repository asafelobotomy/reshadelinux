#!/bin/bash

# VERSION and CHANGELOG consistency.

test_release_metadata_version_matches_changelog_headline() {
    local version_file="$SCRIPT_DIR/../VERSION"
    local changelog_file="$SCRIPT_DIR/../CHANGELOG.md"
    local version changelog_version

    version=$(tr -d '\n' < "$version_file")
    changelog_version=$(grep -m1 '^## \[' "$changelog_file" | sed -E 's/^## \[([^]]+)\].*/\1/')

    [[ -n "$version" ]]
    [[ "$version" == "$changelog_version" ]]
}

test_release_metadata_current_version_is_dated() {
    local version_file="$SCRIPT_DIR/../VERSION"
    local changelog_file="$SCRIPT_DIR/../CHANGELOG.md"
    local version first_release_line

    version=$(tr -d '\n' < "$version_file")
    first_release_line=$(grep -m1 '^## \[' "$changelog_file")

    [[ "$first_release_line" == "## [$version] - "* ]]
    [[ "$first_release_line" != *"Unreleased"* ]]
}

run_release_metadata_tests() {
    echo -e "${BLUE}Release Metadata Tests${NC}"
    run_test "VERSION matches changelog current release" test_release_metadata_version_matches_changelog_headline
    run_test "Current changelog release is dated" test_release_metadata_current_version_is_dated
    echo ""
}
