#!/usr/bin/env bash
# purpose:  Validate the repository, build the AppImage, commit tracked release changes, tag, push, and create or update a GitHub release from the current VERSION and CHANGELOG.
# when:     Use when publishing a new reshadelinux AppImage release from a prepared repository state; do not use for exploratory local builds or when unrelated untracked files are present.
# inputs:   Optional flags: --repo-root PATH, --github-repo OWNER/REPO, --remote NAME, --appimagetool PATH, --skip-tests, --skip-release, --yes.
# outputs:  Writes progress logs to stdout, builds dist/reshadelinux-<version>-x86_64.AppImage, and prints the published release URL unless --skip-release is used.
# risk:     destructive
# source:   original

set -euo pipefail

declare -a CLEANUP_PATHS=()

function cleanup_temp_paths() {
    local path
    for path in "${CLEANUP_PATHS[@]}"; do
        [[ -n "$path" && -e "$path" ]] || continue
        rm -rf "$path"
    done
}

trap cleanup_temp_paths EXIT

function usage() {
    cat <<'EOF'
Usage: release-appimage.sh [options]

Options:
  --repo-root PATH           Repository root. Default: current repository.
  --github-repo OWNER/REPO   GitHub repository for release publishing.
                             Default: asafelobotomy/reshadelinux
  --remote NAME              Git remote to push. Default: origin
  --appimagetool PATH        Existing appimagetool binary to use.
  --skip-tests               Skip bash tests and ShellCheck.
  --skip-release             Build, commit, tag, and push, but do not touch GitHub Releases.
  --yes                      Skip the destructive-operation confirmation prompt.
  --help                     Show this help.

This script reads VERSION and CHANGELOG.md from the repository root.
It refuses to run if non-ignored untracked files are present.
EOF
}

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

function resolve_repo_root() {
    if [[ -n ${REPO_ROOT:-} ]]; then
        cd "$REPO_ROOT" >/dev/null 2>&1 || print_err "Could not access repo root: $REPO_ROOT"
        pwd
        return
    fi

    git rev-parse --show-toplevel 2>/dev/null || print_err "Run this inside a git repository or pass --repo-root"
}

function extract_release_notes() {
    local version="$1"
    local changelog_file="$2"

    awk -v version="$version" '
        $0 ~ ("^## \\[" version "\\]") { capture = 1; next }
        capture && $0 ~ /^## \[/ { exit }
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

function download_appimagetool() {
    local destination="$1"

    python3 - "$destination" <<'PY'
from pathlib import Path
from urllib.request import urlopen
import sys

destination = Path(sys.argv[1])
url = 'https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage'
with urlopen(url) as response:
    destination.write_bytes(response.read())
PY
    chmod +x "$destination"
}

function build_appimage() {
    local repo_root="$1"
    local version="$2"
    local appimagetool_bin="$3"
    local artifact_path="$4"
    local build_root app_dir validation_home validation_main_path

    build_root="$(mktemp -d)"
    CLEANUP_PATHS+=("$build_root")
    app_dir="$build_root/AppDir"

    mkdir -p "$app_dir/usr/bin"
    cp -a "$repo_root/packaging/appimage/AppDir/." "$app_dir/"
    cp "$repo_root/reshadelinux.sh" "$repo_root/reshadelinux-gui.sh" "$repo_root/VERSION" "$app_dir/usr/bin/"
    cp -a "$repo_root/lib" "$app_dir/usr/bin/"

    # Stamp the current version into the desktop entry.
    sed -i "s/^X-AppImage-Version=.*/X-AppImage-Version=$version/" \
        "$app_dir/io.github.asafelobotomy.reshadelinux.desktop"

        # Reuse the packaged PNG icon so README and AppImage branding stay in sync.
    ln -sf reshadelinux.png "$app_dir/.DirIcon"

        # Install the icon in hicolor so AppImage managers find it.
    local _icon_dir="$app_dir/usr/share/icons/hicolor"
        mkdir -p "$_icon_dir/256x256/apps"
    cp "$app_dir/reshadelinux.png" "$_icon_dir/256x256/apps/reshadelinux.png"

    # Install AppStream metainfo.
    mkdir -p "$app_dir/usr/share/metainfo"
    cp "$app_dir/io.github.asafelobotomy.reshadelinux.metainfo.xml" "$app_dir/usr/share/metainfo/"

    mkdir -p "$(dirname "$artifact_path")"

    ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$appimagetool_bin" "$app_dir" "$artifact_path"
    validation_home="$build_root/home"
    validation_main_path="$build_root/validation-main"
    mkdir -p "$validation_home"
    APPIMAGE_EXTRACT_AND_RUN=1 HOME="$validation_home" MAIN_PATH="$validation_main_path" "$artifact_path" --update-all >/dev/null
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

ASSUME_YES=0
SKIP_TESTS=0
SKIP_RELEASE=0
GITHUB_REPO="asafelobotomy/reshadelinux"
REMOTE_NAME="origin"
APPIMAGETOOL_BIN=""
REPO_ROOT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-root)
            REPO_ROOT="$2"
            shift 2
            ;;
        --github-repo)
            GITHUB_REPO="$2"
            shift 2
            ;;
        --remote)
            REMOTE_NAME="$2"
            shift 2
            ;;
        --appimagetool)
            APPIMAGETOOL_BIN="$2"
            shift 2
            ;;
        --skip-tests)
            SKIP_TESTS=1
            shift
            ;;
        --skip-release)
            SKIP_RELEASE=1
            shift
            ;;
        --yes)
            ASSUME_YES=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            print_err "Unknown argument: $1"
            ;;
    esac
done

REPO_ROOT="$(resolve_repo_root)"
VERSION_FILE="$REPO_ROOT/VERSION"
CHANGELOG_FILE="$REPO_ROOT/CHANGELOG.md"
TEMP_DIR="$(mktemp -d)"
CLEANUP_PATHS+=("$TEMP_DIR")

require_command git
require_command gh
require_command shellcheck
require_command python3

[[ -f "$VERSION_FILE" ]] || print_err "Missing VERSION file at $VERSION_FILE"
[[ -f "$CHANGELOG_FILE" ]] || print_err "Missing CHANGELOG.md at $CHANGELOG_FILE"

VERSION="$(tr -d '\n' < "$VERSION_FILE")"
TAG_NAME="v$VERSION"
ARTIFACT_PATH="$REPO_ROOT/dist/reshadelinux-${VERSION}-x86_64.AppImage"
NOTES_FILE="$TEMP_DIR/release-notes.md"

extract_release_notes "$VERSION" "$CHANGELOG_FILE" > "$NOTES_FILE"
[[ -s "$NOTES_FILE" ]] || print_err "Could not extract release notes for version $VERSION from CHANGELOG.md"

print_step "Release plan"
print_info "repo root: $REPO_ROOT"
print_info "version: $VERSION"
print_info "tag: $TAG_NAME"
print_info "artifact: $ARTIFACT_PATH"
print_info "remote: $REMOTE_NAME"
print_info "github repo: $GITHUB_REPO"
if [[ $SKIP_RELEASE -eq 1 ]]; then
    print_info "github release: skipped"
fi

if [[ $ASSUME_YES -ne 1 ]]; then
    read -r -p 'Proceed with build, commit, tag, push, and release steps? [y/N] ' confirmation
    [[ "$confirmation" =~ ^[Yy]$ ]] || print_err "Release aborted by user"
fi

print_step "Checking repository state"
ensure_no_untracked_files "$REPO_ROOT"

if [[ $SKIP_TESTS -ne 1 ]]; then
    print_step "Running validation"
    (
        cd "$REPO_ROOT"
        bash tests/run_simple_tests.sh
        shellcheck lib/*.sh reshadelinux.sh reshadelinux-gui.sh scripts/diagnostics/*.sh tests/*.sh
    )
fi

print_step "Preparing appimagetool"
if [[ -n "$APPIMAGETOOL_BIN" ]]; then
    [[ -x "$APPIMAGETOOL_BIN" ]] || print_err "appimagetool is not executable: $APPIMAGETOOL_BIN"
else
    APPIMAGETOOL_BIN="$TEMP_DIR/appimagetool-x86_64.AppImage"
    download_appimagetool "$APPIMAGETOOL_BIN"
fi

print_step "Building AppImage"
build_appimage "$REPO_ROOT" "$VERSION" "$APPIMAGETOOL_BIN" "$ARTIFACT_PATH"
print_info "built: $ARTIFACT_PATH"

print_step "Committing tracked changes"
if ! git -C "$REPO_ROOT" diff --quiet || ! git -C "$REPO_ROOT" diff --cached --quiet; then
    git -C "$REPO_ROOT" add -A
    git -C "$REPO_ROOT" commit -m "chore(release): publish $TAG_NAME"
else
    print_info "no tracked changes to commit"
fi

print_step "Tagging release"
ensure_release_tag "$REPO_ROOT" "$TAG_NAME"

print_step "Pushing branch and tag"
git -C "$REPO_ROOT" push "$REMOTE_NAME" HEAD
git -C "$REPO_ROOT" push "$REMOTE_NAME" "$TAG_NAME"

if [[ $SKIP_RELEASE -ne 1 ]]; then
    print_step "Publishing GitHub release"
    create_or_update_release "$GITHUB_REPO" "$TAG_NAME" "$NOTES_FILE" "$ARTIFACT_PATH"
    RELEASE_URL="$(gh release view "$TAG_NAME" -R "$GITHUB_REPO" --json url --jq '.url')"
    print_info "release url: $RELEASE_URL"
fi

print_step "Done"
print_info "artifact: $ARTIFACT_PATH"
if [[ $SKIP_RELEASE -ne 1 ]]; then
    print_info "tag: $TAG_NAME"
fi