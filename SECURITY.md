# Security policy

## Supported versions

Only the latest release receives fixes. Please reproduce a problem on the newest release, or on `main`, before reporting it.

## Reporting a vulnerability

Report privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. If that option is not available, open an issue that says you have a security report and asks for a private channel, and leave out the details of the problem.

Please include the version (`./reshadelinux.sh --version`), how you run it (source checkout or AppImage), and the smallest set of steps that shows the problem. You can expect an acknowledgement within a week.

## What is in scope

- Downloads: the ReShade installer URL check, the optional `RESHADE_SETUP_SHA256` pin, the pinned `d3dcompiler_47.dll`, and the pinned `appimagetool` used for releases.
- File handling: anything that lets input (a game path, a DLL name, a repository name, a state file) write, link or delete outside the intended game or `MAIN_PATH` directory.
- Packaging: the AppImage contents and the release tooling in `scripts/release/`.

## What to know about shader packs

Shader repositories in the built-in registry belong to third parties. They are cloned over HTTPS at the head of their default branch and are not pinned to a commit. Shader files are compiled by ReShade; they are not run as native code by this installer. If you want to review or freeze a pack, set `SHADER_REPOS` to your own list or place vetted files in `External_shaders/`.

`RESHADE_SETUP_SHA256` is opt-in: without it the ReShade installer is accepted from the official hosts (`reshade.me` and `static.reshade.me`) over HTTPS with no hash check, because the project publishes no digest to compare against.
