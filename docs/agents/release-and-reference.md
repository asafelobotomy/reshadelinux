# Release and reference

Moved from CLAUDE.md (the Conventional Commits rule stays there). Read before cutting a release, bumping versions or pins, or auditing the shader registry.

## Release

- The version appears in `VERSION`, the fallback string in `reshadelinux.sh`, `X-AppImage-Version` in the desktop entry, the metainfo `<release>` list and `CHANGELOG.md`. Change them together; `scripts/release/check-version-sync.sh` (run by the tests and the release tool) fails if they disagree.
- `CHANGELOG.md` uses Keep a Changelog headings. The first *versioned* heading must match `VERSION` and be dated; an `## [Unreleased]` section above it is allowed.
- Before a release, run `scripts/release/pin-reshade.sh` (pins the ReShade build reshade.me offers) and `scripts/release/pin-shader-repos.sh`, review what moved, and commit the pin files with the release.
- `scripts/release/release-appimage.sh --build-only` builds and validates the AppImage with no git or GitHub side effects. A real release must start on `main` with only the version files changed. `appimagetool` is pinned by checksum in `packaging/appimagetool.sha256`.

## Reference

- The official shader package list is `EffectPackages.ini` on the `list` branch of `crosire/reshade-shaders`. Compare `SHADER_REPOS` against it when auditing the registry.
- `docs/research/` holds unimplemented ideas (shell completion, richer `--version`). Remove an idea once it is implemented.
