# shellcheck shell=bash
# SPDX-License-Identifier: GPL-2.0-or-later

# Where a shader repository keeps its content, and whether it can share the flat merged
# Shaders directory with the other selected repositories.

# Print the directory a shader repo keeps its content in ($2 is "Shaders" or
# "Textures"). Repositories differ in case ("Shaders", "shaders"): Linux paths are
# case-sensitive while ReShade under Wine is not, so authors never notice, and an
# exact-case search would silently find nothing. An exact match wins, then any case
# directly under the root, then a bounded search below it ($3=shallow skips that).
function _findRepoContentDir() {
    local _root="$1" _name="$2" _mode="${3:-deep}" _dir

    for _dir in "$_root/$_name" "$_root/${_name,,}" "$_root/${_name^^}"; do
        [[ -d $_dir ]] && { printf '%s\n' "$_dir"; return 0; }
    done
    _dir=$(find "$_root" -mindepth 1 -maxdepth 1 -type d -iname "$_name" -print -quit)
    if [[ -z $_dir && $_mode != shallow ]]; then
        _dir=$(find "$_root" \
            -maxdepth 4 \
            \( -path '*/.git' -o -path '*/.github' -o -path '*/download' \) -prune -o \
            -type d -iname "$_name" -print -quit)
    fi
    [[ -n $_dir ]] && printf '%s\n' "$_dir"
    return 0
}

# True when a repo keeps effects at its top level instead of in Shaders/ (for
# example a single-shader repo such as ReshadeTFAA).
function _repoHasRootLevelEffects() {
    compgen -G "$1/*.fx" >/dev/null
}

# Link every .fx/.fxh of a repo without a Shaders/ directory into the merged Shaders
# folder, keeping relative paths so includes such as "./lib/x.fxh" resolve. Only shader
# sources are linked: the repo root also holds docs, images and .git.
function _linkRootLevelEffectsTo() {
    local _repoRoot="$1" _outBase="$2" _file _target

    while IFS= read -r -d '' _file; do
        _target="$_outBase/Shaders/${_file#"$_repoRoot"/}"
        [[ -e $_target || -L $_target ]] && continue
        mkdir -p "${_target%/*}"
        ln -s "$(realpath "$_file")" "$_target"
    done < <(find "$_repoRoot" \( -name .git -o -name .github \) -prune -o \
        -type f \( -name '*.fx' -o -name '*.fxh' \) -print0)
}

# Report files of a repo that the merged Shaders directory already has with different
# content: the first copy is kept, so a pack that ships its own header (BFBFX and ZenteonFX
# both ship a ZenteonCommon.fxh) may compile against the other's, or lose an effect. Headers
# are worth a visible warning; a duplicate effect name is only logged.
function _reportConflictingShaderFiles() {
    local _repoRoot="$1" _outBase="$2" _name="$3" _shadersDir _file _rel

    _shadersDir=$(_findRepoContentDir "$_repoRoot" Shaders)
    if [[ -z $_shadersDir ]]; then
        _repoHasRootLevelEffects "$_repoRoot" || return 0
        _shadersDir="$_repoRoot"
    fi
    while IFS= read -r -d '' _file; do
        _rel="${_file#"$_shadersDir"/}"
        [[ -e "$_outBase/Shaders/$_rel" ]] || continue
        cmp -s "$_file" "$_outBase/Shaders/$_rel" && continue
        if [[ $_file == *.fxh ]]; then
            printf '%bWarning: %s ships its own %s, but a different copy is already merged and is used for every effect.%b\n' \
                "$_YLW" "$_name" "$_rel" "$_R"
        else
            logDebug "Skipping $_name/$_rel: a different file with that name is already merged"
        fi
    done < <(find "$_shadersDir" \( -name .git -o -name .github \) -prune -o \
        -type f \( -name '*.fx' -o -name '*.fxh' \) -print0)
    return 0
}
