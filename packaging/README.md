# Packaging

Packaging assets live here so the repository root stays focused on user-facing entrypoints, libraries, tests, and core project metadata.

## AppImage

- `appimage/AppDir/` - AppImage runtime assets including `AppRun`, desktop metadata, and icons

The AppImage release tool in `scripts/release/release-appimage.sh` reads from this directory when assembling a release build.

`appimagetool.sha256` pins the SHA-256 of the `appimagetool` release the tool downloads (currently 1.9.1 from `AppImage/appimagetool`). The tool refuses to run any binary that does not match it. To move to a newer release, download it with `gh release download`, check its digest against the value GitHub shows for the asset, and update both the checksum here and `APPIMAGETOOL_VERSION` in `scripts/release/lib-release.sh`.
