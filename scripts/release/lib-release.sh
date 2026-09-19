# shellcheck shell=bash
# Helpers for release-appimage.sh. Sourced, never executed: defining a function has no
# side effects, so the tests can exercise each one.

# appimagetool is downloaded from a versioned release and must match this digest.
APPIMAGETOOL_VERSION="1.9.1"
APPIMAGETOOL_REPO="AppImage/appimagetool"
APPIMAGETOOL_ASSET="appimagetool-x86_64.AppImage"

# The only tracked files a release run may commit: they carry the version.
RELEASE_FILES=(
    VERSION
    CHANGELOG.md
    reshadelinux.sh
    packaging/appimage/AppDir/io.github.asafelobotomy.reshadelinux.metainfo.xml
    packaging/appimage/AppDir/io.github.asafelobotomy.reshadelinux.desktop
)

function print_step() {
    printf '\n==> %s\n' "$1"
}

function print_info() {
    printf '  %s\n' "$1"
}

function print_err() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

function require_command() {
    command -v "$1" >/dev/null 2>&1 || print_err "Required command not found: $1"
}

# Print the changelog section body for a version (heading excluded).
function extract_release_notes() {
    local version="$1"
    local changelog_file="$2"

    awk -v version="$version" '
        index($0, "## [" version "]") == 1 { capture = 1; next }
        capture && /^## \[/ { exit }
        capture { print }
    ' "$changelog_file"
}

function ensure_no_untracked_files() {
    local repo_root="$1"
    local -a untracked_files=()

    mapfile -t untracked_files < <(git -C "$repo_root" ls-files --others --exclude-standard)
    if (( ${#untracked_files[@]} > 0 )); then
        printf 'Refusing to continue with untracked files present:\n' >&2
        printf '  %s\n' "${untracked_files[@]}" >&2
        exit 1
    fi
}

# Tracked changes are allowed only in the files that carry the version, so an
# unrelated edit can never ride along in the release commit.
function ensure_only_release_files_changed() {
    local repo_root="$1" changed allowed
    local -a unexpected=()

    while IFS= read -r changed; do
        [[ -n $changed ]] || continue
        for allowed in "${RELEASE_FILES[@]}"; do
            [[ $changed == "$allowed" ]] && continue 2
        done
        unexpected+=("$changed")
    done < <(git -C "$repo_root" diff --name-only HEAD)

    if (( ${#unexpected[@]} > 0 )); then
        printf 'Refusing to release with unrelated tracked changes:\n' >&2
        printf '  %s\n' "${unexpected[@]}" >&2
        exit 1
    fi
}

function ensure_release_branch() {
    local repo_root="$1" expected="${2:-main}" current

    current="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD)"
    [[ $current == "$expected" ]] || print_err "Releases are made from '$expected', but the current branch is '$current'."
}

function ensure_release_tag() {
    local repo_root="$1"
    local tag_name="$2"

    if git -C "$repo_root" rev-parse -q --verify "refs/tags/$tag_name" >/dev/null 2>&1; then
        local tag_commit head_commit
        tag_commit="$(git -C "$repo_root" rev-list -n 1 "$tag_name")"
        head_commit="$(git -C "$repo_root" rev-parse HEAD)"
        [[ "$tag_commit" == "$head_commit" ]] || print_err "Tag $tag_name already exists but does not point at HEAD"
        return
    fi

    git -C "$repo_root" tag -a "$tag_name" -m "Release $tag_name"
}

# Compare a file against the sha256 recorded in the pin file (sha256sum format).
# $1 = file to check  $2 = pin file
function verify_appimagetool_hash() {
    local file="$1" pin_file="$2" expected actual _

    [[ -f $pin_file ]] || print_err "Missing appimagetool checksum file: $pin_file"
    read -r expected _ < "$pin_file"
    [[ $expected =~ ^[0-9a-fA-F]{64}$ ]] || print_err "Malformed appimagetool checksum in $pin_file"
    [[ -f $file ]] || print_err "appimagetool not found: $file"

    read -r actual _ < <(sha256sum "$file")
    [[ ${actual,,} == "${expected,,}" ]] \
        || print_err "appimagetool checksum mismatch for $file (expected $expected, got $actual)"
}

# Fetch the pinned appimagetool release with gh and verify it before it is ever run.
# $1 = destination path  $2 = pin file
function fetch_appimagetool() {
    local destination="$1" pin_file="$2" download_dir

    download_dir="$(mktemp -d)"
    gh release download "$APPIMAGETOOL_VERSION" -R "$APPIMAGETOOL_REPO" \
        -p "$APPIMAGETOOL_ASSET" -D "$download_dir" \
        || { rm -rf "$download_dir"; print_err "Could not download appimagetool $APPIMAGETOOL_VERSION"; }
    mv "$download_dir/$APPIMAGETOOL_ASSET" "$destination"
    rm -rf "$download_dir"
    verify_appimagetool_hash "$destination" "$pin_file"
    chmod +x "$destination"
}

function create_or_update_release() {
    local github_repo="$1"
    local tag_name="$2"
    local notes_file="$3"
    local artifact_path="$4"

    if gh release view "$tag_name" -R "$github_repo" >/dev/null 2>&1; then
        gh release edit "$tag_name" -R "$github_repo" --title "$tag_name" --notes-file "$notes_file"
        gh release upload "$tag_name" "$artifact_path#$(basename "$artifact_path")" -R "$github_repo" --clobber
    else
        gh release create "$tag_name" "$artifact_path#$(basename "$artifact_path")" -R "$github_repo" --title "$tag_name" --notes-file "$notes_file"
    fi
}
