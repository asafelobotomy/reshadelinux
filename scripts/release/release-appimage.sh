#!/usr/bin/env bash
# purpose:  Validate the repository, build the AppImage and, unless --build-only is given, commit the version files, tag, push and publish a GitHub release from VERSION and CHANGELOG.md.
# when:     Use --build-only for an exploratory build with no git or GitHub side effects. A release run must start on main with only the version files changed.
# inputs:   Flags: --repo-root PATH, --github-repo OWNER/REPO, --remote NAME, --appimagetool PATH, --skip-tests, --skip-release, --build-only, --yes.
# outputs:  Progress on stdout, dist/reshadelinux-<version>-x86_64.AppImage, and the release URL after a full release.
# risk:     destructive (a release run pushes commits and tags and edits GitHub releases; --build-only does not)
# source:   original
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-release.sh
source "$SCRIPT_DIR/lib-release.sh"

declare -a CLEANUP_PATHS=()

function cleanup_temp_paths() {
    local path
    for path in "${CLEANUP_PATHS[@]}"; do
        [[ -n "$path" && -e "$path" ]] || continue
        rm -rf "$path"
    done
}

function usage() {
    cat <<'EOF'
Usage: release-appimage.sh [options]

Options:
  --build-only               Validate and build the AppImage only. Nothing is
                             committed, tagged, pushed or published, and the branch
                             and working-tree checks are skipped.
  --repo-root PATH           Repository root. Default: current repository.
  --github-repo OWNER/REPO   GitHub repository for release publishing.
                             Default: asafelobotomy/reshadelinux
  --remote NAME              Git remote to push. Default: origin
  --appimagetool PATH        Existing appimagetool binary. It must match the pinned
                             checksum in packaging/appimagetool.sha256.
  --skip-tests               Skip the test suite and ShellCheck.
  --skip-release             Commit, tag and push, but do not touch GitHub Releases.
  --yes                      Skip the confirmation prompt.
  --help                     Show this help.

A release run must start on main. The only tracked files that may have changed are
the ones that carry the version (VERSION, CHANGELOG.md, reshadelinux.sh, the
AppStream metainfo and the desktop entry), and no untracked files may exist.
The version is checked for consistency across those files first.
EOF
}

function parse_args() {
    ASSUME_YES=0
    SKIP_TESTS=0
    SKIP_RELEASE=0
    BUILD_ONLY=0
    GITHUB_REPO="asafelobotomy/reshadelinux"
    REMOTE_NAME="origin"
    APPIMAGETOOL_BIN=""
    REPO_ROOT=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo-root) REPO_ROOT="$2"; shift 2 ;;
            --github-repo) GITHUB_REPO="$2"; shift 2 ;;
            --remote) REMOTE_NAME="$2"; shift 2 ;;
            --appimagetool) APPIMAGETOOL_BIN="$2"; shift 2 ;;
            --skip-tests) SKIP_TESTS=1; shift ;;
            --skip-release) SKIP_RELEASE=1; shift ;;
            --build-only) BUILD_ONLY=1; shift ;;
            --yes) ASSUME_YES=1; shift ;;
            --help|-h) usage; exit 0 ;;
            *) print_err "Unknown argument: $1" ;;
        esac
    done
}

function resolve_repo_root() {
    if [[ -n ${REPO_ROOT:-} ]]; then
        cd "$REPO_ROOT" >/dev/null 2>&1 || print_err "Could not access repo root: $REPO_ROOT"
        pwd
        return
    fi

    git rev-parse --show-toplevel 2>/dev/null || print_err "Run this inside a git repository or pass --repo-root"
}

function ensure_release_preconditions() {
    local repo_root="$1"

    ensure_release_branch "$repo_root" main
    ensure_only_release_files_changed "$repo_root"
    ensure_no_untracked_files "$repo_root"
}

function run_validation() {
    local repo_root="$1"

    (
        local -a shell_files=()

        cd "$repo_root"
        bash tests/run_simple_tests.sh
        mapfile -t shell_files < <(git ls-files '*.sh')
        shellcheck -- "${shell_files[@]}" packaging/appimage/AppDir/AppRun
    )
}

# Leave the verified appimagetool path in APPIMAGETOOL_BIN.
function prepare_appimagetool() {
    local repo_root="$1" temp_dir="$2" pin_file="$1/packaging/appimagetool.sha256"

    if [[ -n $APPIMAGETOOL_BIN ]]; then
        [[ -x "$APPIMAGETOOL_BIN" ]] || print_err "appimagetool is not executable: $APPIMAGETOOL_BIN"
        verify_appimagetool_hash "$APPIMAGETOOL_BIN" "$pin_file"
        return
    fi

    APPIMAGETOOL_BIN="$temp_dir/$APPIMAGETOOL_ASSET"
    fetch_appimagetool "$APPIMAGETOOL_BIN" "$pin_file"
}

function build_appimage() {
    local repo_root="$1" version="$2" appimagetool_bin="$3" artifact_path="$4"
    local build_root app_dir icon_dir

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

    # Reuse the packaged PNG icon so README and AppImage branding stay in sync, and
    # install it in hicolor so AppImage managers find it.
    ln -sf reshadelinux.png "$app_dir/.DirIcon"
    icon_dir="$app_dir/usr/share/icons/hicolor/256x256/apps"
    mkdir -p "$icon_dir"
    cp "$app_dir/reshadelinux.png" "$icon_dir/reshadelinux.png"

    mkdir -p "$app_dir/usr/share/metainfo"
    cp "$app_dir/io.github.asafelobotomy.reshadelinux.metainfo.xml" "$app_dir/usr/share/metainfo/"

    mkdir -p "$(dirname "$artifact_path")"
    ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$appimagetool_bin" "$app_dir" "$artifact_path"
}

# Run the built AppImage: it must report the release version, and --update-all must
# complete offline against an empty state store.
function validate_artifact() {
    local artifact_path="$1" version="$2"
    local validation_root reported

    validation_root="$(mktemp -d)"
    CLEANUP_PATHS+=("$validation_root")
    mkdir -p "$validation_root/home"

    reported="$(APPIMAGE_EXTRACT_AND_RUN=1 HOME="$validation_root/home" MAIN_PATH="$validation_root/main" \
        "$artifact_path" --version 2>/dev/null)"
    [[ $reported == "$version" ]] || print_err "AppImage reports version '$reported', expected '$version'"

    APPIMAGE_EXTRACT_AND_RUN=1 HOME="$validation_root/home" MAIN_PATH="$validation_root/main" \
        "$artifact_path" --update-all >/dev/null
}

function commit_release_changes() {
    local repo_root="$1" tag_name="$2"

    if git -C "$repo_root" diff --quiet HEAD -- "${RELEASE_FILES[@]}"; then
        print_info "no version-file changes to commit"
        return
    fi
    git -C "$repo_root" add -- "${RELEASE_FILES[@]}"
    git -C "$repo_root" commit -m "chore(release): publish $tag_name"
}

function push_release() {
    local repo_root="$1" remote_name="$2" tag_name="$3"

    git -C "$repo_root" push "$remote_name" HEAD
    git -C "$repo_root" push "$remote_name" "$tag_name"
}

function publish_release() {
    local github_repo="$1" tag_name="$2" notes_file="$3" artifact_path="$4" release_url

    create_or_update_release "$github_repo" "$tag_name" "$notes_file" "$artifact_path"
    release_url="$(gh release view "$tag_name" -R "$github_repo" --json url --jq '.url')"
    print_info "release url: $release_url"
}

function main() {
    local repo_root version tag_name artifact_path temp_dir notes_file confirmation

    parse_args "$@"
    trap cleanup_temp_paths EXIT

    repo_root="$(resolve_repo_root)"
    temp_dir="$(mktemp -d)"
    CLEANUP_PATHS+=("$temp_dir")
    notes_file="$temp_dir/release-notes.md"

    require_command git
    [[ -f "$repo_root/VERSION" ]] || print_err "Missing VERSION file at $repo_root/VERSION"
    [[ -f "$repo_root/CHANGELOG.md" ]] || print_err "Missing CHANGELOG.md at $repo_root/CHANGELOG.md"
    [[ $SKIP_TESTS -eq 1 ]] || require_command shellcheck
    # gh downloads the pinned appimagetool and publishes the release.
    if [[ -z $APPIMAGETOOL_BIN ]] || [[ $BUILD_ONLY -ne 1 && $SKIP_RELEASE -ne 1 ]]; then
        require_command gh
    fi

    print_step "Checking version consistency"
    "$repo_root/scripts/release/check-version-sync.sh" "$repo_root" || print_err "Version files disagree; fix them before releasing"

    version="$(tr -d '\n' < "$repo_root/VERSION")"
    tag_name="v$version"
    artifact_path="$repo_root/dist/reshadelinux-${version}-x86_64.AppImage"
    extract_release_notes "$version" "$repo_root/CHANGELOG.md" > "$notes_file"
    [[ -s $notes_file ]] || print_err "Could not extract release notes for version $version from CHANGELOG.md"

    print_step "Release plan"
    print_info "repo root: $repo_root"
    print_info "version: $version"
    print_info "artifact: $artifact_path"
    if [[ $BUILD_ONLY -eq 1 ]]; then
        print_info "mode: build only (no commit, tag, push or release)"
    else
        print_info "tag: $tag_name"
        print_info "remote: $REMOTE_NAME"
        print_info "github repo: $GITHUB_REPO"
        [[ $SKIP_RELEASE -ne 1 ]] || print_info "github release: skipped"

        if [[ $ASSUME_YES -ne 1 ]]; then
            read -r -p 'Proceed with build, commit, tag, push, and release steps? [y/N] ' confirmation
            [[ "$confirmation" =~ ^[Yy]$ ]] || print_err "Release aborted by user"
        fi
        print_step "Checking repository state"
        ensure_release_preconditions "$repo_root"
    fi

    if [[ $SKIP_TESTS -ne 1 ]]; then
        print_step "Running validation"
        run_validation "$repo_root"
    fi

    print_step "Preparing appimagetool"
    prepare_appimagetool "$repo_root" "$temp_dir"

    print_step "Building AppImage"
    build_appimage "$repo_root" "$version" "$APPIMAGETOOL_BIN" "$artifact_path"
    validate_artifact "$artifact_path" "$version"
    print_info "built and validated: $artifact_path"

    if [[ $BUILD_ONLY -eq 1 ]]; then
        print_step "Done (build only)"
        return
    fi

    print_step "Committing version files"
    commit_release_changes "$repo_root" "$tag_name"

    print_step "Tagging release"
    ensure_release_tag "$repo_root" "$tag_name"

    print_step "Pushing branch and tag"
    push_release "$repo_root" "$REMOTE_NAME" "$tag_name"

    if [[ $SKIP_RELEASE -ne 1 ]]; then
        print_step "Publishing GitHub release"
        publish_release "$GITHUB_REPO" "$tag_name" "$notes_file" "$artifact_path"
    fi

    print_step "Done"
    print_info "artifact: $artifact_path"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
