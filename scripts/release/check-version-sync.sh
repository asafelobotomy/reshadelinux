#!/usr/bin/env bash
# purpose:  Verify that every place the version is recorded agrees with VERSION.
# when:     Before building or publishing a release; the test suite runs it too.
# inputs:   Optional repository root (default: the repository containing this script).
# outputs:  One "Version mismatch" line per problem on stderr. Exit status 1 when
#           anything disagrees, 0 when all places are consistent.
# risk:     safe (read-only)
# source:   original
set -euo pipefail

root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
metainfo_file="$root/packaging/appimage/AppDir/io.github.asafelobotomy.reshadelinux.metainfo.xml"
desktop_file="$root/packaging/appimage/AppDir/io.github.asafelobotomy.reshadelinux.desktop"
failures=0

function fail() {
    printf 'Version mismatch: %s\n' "$*" >&2
    failures=$((failures + 1))
}

version="$(tr -d '[:space:]' < "$root/VERSION")"
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "VERSION is '$version', expected MAJOR.MINOR.PATCH"
fi

# The first versioned heading counts as the current release. A "## [Unreleased]"
# section above it is allowed.
changelog_line="$(grep -m1 -E '^## \[[0-9]' "$root/CHANGELOG.md" || true)"
changelog_version="$(sed -nE 's/^## \[([^]]+)\].*/\1/p' <<< "$changelog_line")"
changelog_date="$(sed -nE 's/^## \[[^]]+\] - ([0-9]{4}-[0-9]{2}-[0-9]{2})$/\1/p' <<< "$changelog_line")"
if [[ $changelog_version != "$version" ]]; then
    fail "CHANGELOG.md top release is '${changelog_version:-none}' but VERSION is '$version'"
fi
if [[ -z $changelog_date ]]; then
    fail "CHANGELOG.md release '$version' has no ISO date (expected '## [$version] - YYYY-MM-DD')"
fi

metainfo_release="$(grep -m1 -oE '<release version="[^"]+" date="[^"]+"' "$metainfo_file" || true)"
metainfo_version="$(sed -nE 's/<release version="([^"]+)".*/\1/p' <<< "$metainfo_release")"
metainfo_date="$(sed -nE 's/.*date="([^"]+)".*/\1/p' <<< "$metainfo_release")"
if [[ $metainfo_version != "$version" ]]; then
    fail "AppStream metainfo top release is '${metainfo_version:-none}' but VERSION is '$version'"
fi
if [[ -n $changelog_date && $metainfo_date != "$changelog_date" ]]; then
    fail "AppStream metainfo release date is '${metainfo_date:-none}' but CHANGELOG.md says '$changelog_date'"
fi

script_fallback="$(grep -m1 -oE "printf '[0-9][^']*'" "$root/reshadelinux.sh" | sed -E "s/printf '([^']*)'/\1/" || true)"
if [[ $script_fallback != "$version" ]]; then
    fail "reshadelinux.sh fallback version is '${script_fallback:-none}' but VERSION is '$version'"
fi

desktop_version="$(sed -nE 's/^X-AppImage-Version=(.*)$/\1/p' "$desktop_file" | head -n1)"
if [[ $desktop_version != "$version" ]]; then
    fail "desktop entry X-AppImage-Version is '${desktop_version:-none}' but VERSION is '$version'"
fi

if [[ $failures -gt 0 ]]; then
    exit 1
fi
printf 'Version %s is consistent across VERSION, CHANGELOG.md, metainfo, reshadelinux.sh and the desktop entry.\n' "$version"
