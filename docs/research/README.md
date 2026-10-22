# Research

Ideas that are not implemented yet. Remove an entry once it ships.

## Shell completion

bash and zsh completion for the flags and for `--shader-repos=` (the names from `--list-shader-repos --json`).
[clig.dev](https://clig.dev) and the 12 Factor CLI article both recommend it. Needs a decision on where the
completion files are installed from an AppImage.

## A richer `--version`

Print how the installer runs (AppImage or source checkout), whether Steam is native or Flatpak, and the
ReShade build in use, so a bug report starts with the facts that matter. Keep plain `--version` output a
single version line for scripts, and put the rest behind `--version --verbose` or in `--help`.

## Conventions of comparable tools

vkBasalt, Protontricks, Heroic and Bottles were not reviewed for flag names and behaviour worth matching.
