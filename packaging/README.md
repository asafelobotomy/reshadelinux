# Packaging

Packaging assets live here so the repository root stays focused on user-facing entrypoints, libraries, tests, and core project metadata.

## AppImage

- `appimage/AppDir/` - AppImage runtime assets including `AppRun`, desktop metadata, and icons

The AppImage release tool in `.copilot/tools/release-appimage.sh` reads from this directory when assembling a release build.
