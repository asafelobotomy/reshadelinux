#!/usr/bin/env bash
# purpose:  Clone each configured shader repository into an isolated workspace and verify that download, layout discovery, and merged per-game output all work.
# when:     Use to audit all configured shader repos or a selected subset; do not use when you need to touch the real user workspace.
# inputs:   Optional positional repo names; optional env vars TMPDIR, SHADER_AUDIT_KEEP_WORKSPACE=0|1, and SHADER_REPOS override.
# outputs:  Per-repo PASS/FAIL lines, a summary, and SHADER_AUDIT_RESULT=PASS|FAIL on stdout.
# risk:     safe
# source:   original
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

AUDIT_ROOT=""

count_source_shader_files() {
    local dir_path="$1"
    [[ -d $dir_path ]] || {
        printf '0\n'
        return
    }
    find "$dir_path" -type f \( -name '*.fx' -o -name '*.fxh' \) | wc -l | awk '{print $1}'
}

count_regular_files() {
    local dir_path="$1"
    [[ -d $dir_path ]] || {
        printf '0\n'
        return
    }
    find "$dir_path" -type f | wc -l | awk '{print $1}'
}

count_merged_entries() {
    local dir_path="$1"
    [[ -d $dir_path ]] || {
        printf '0\n'
        return
    }
    find "$dir_path" \( -type f -o -type l \) | wc -l | awk '{print $1}'
}

find_repo_asset_dir() {
    local repo_root="$1"
    local dir_name="$2"
    local dir_path=""

    if [[ -d "$repo_root/$dir_name" ]]; then
        dir_path="$repo_root/$dir_name"
    else
        dir_path=$(find "$repo_root" \
            -maxdepth 4 \
            \( -path '*/.git' -o -path '*/.github' -o -path '*/download' \) -prune -o \
            -type d -name "$dir_name" -print -quit)
    fi

    printf '%s\n' "$dir_path"
}

list_shader_repo_entries() {
    local -A seen=()
    local saved_ifs="$IFS"
    local entry

    IFS=';' read -ra all_repos <<< "$SHADER_REPOS"
    IFS="$saved_ifs"
    for entry in "${all_repos[@]}"; do
        parseShaderRepoEntry "$entry"
        [[ -z $_shaderRepoName ]] && continue
        [[ -n ${seen["$_shaderRepoName"]+x} ]] && continue
        seen["$_shaderRepoName"]=1
        printf '%s|%s|%s|%s\n' "$_shaderRepoName" "$_shaderRepoUri" "$_shaderRepoBranch" "$_shaderRepoDesc"
    done
}

resolve_shader_repo_entry() {
    local wanted_name="$1"
    while IFS= read -r entry; do
        [[ ${entry%%|*} == "$wanted_name" ]] && {
            printf '%s\n' "$entry"
            return 0
        }
    done < <(list_shader_repo_entries)
    return 1
}

prepare_audit_workspace() {
    local audit_root="$1"

    export HOME="$audit_root/home"
    export XDG_CACHE_HOME="$audit_root/cache"
    export MAIN_PATH="$audit_root/reshade"
    export RESHADE_PATH="$MAIN_PATH/reshade"
    export UI_BACKEND=cli
    export PROGRESS_UI=0
    export UPDATE_RESHADE=0
    export GIT_TERMINAL_PROMPT=0
    export RESHADE_DEBUG_LOG="$audit_root/audit.log"
    mkdir -p "$HOME" "$XDG_CACHE_HOME" "$RESHADE_PATH" "$MAIN_PATH/ReShade_shaders" "$MAIN_PATH/External_shaders" "$MAIN_PATH/game-shaders"
    init_runtime_config
}

audit_shader_repo() {
    local repo_name="$1"
    local repo_uri="$2"
    local repo_root="$MAIN_PATH/ReShade_shaders/$repo_name"
    local shader_dir=""
    local texture_dir=""
    local game_key="audit-$repo_name"
    local game_dir="$AUDIT_ROOT/games/$repo_name"
    local source_shader_count=0
    local source_texture_count=0
    local merged_shader_count=0
    local merged_texture_count=0
    local result="PASS"
    local reason=""

    printf '==> Auditing shader repo: %s\n' "$repo_name"
    if ! ensureSelectedShaderRepos "$repo_name" >/dev/null 2>&1; then
        printf 'FAIL | %s | clone/update failed | uri=%s\n' "$repo_name" "$repo_uri"
        return 1
    fi

    shader_dir=$(find_repo_asset_dir "$repo_root" "Shaders")
    texture_dir=$(find_repo_asset_dir "$repo_root" "Textures")
    source_shader_count=$(count_source_shader_files "$shader_dir")
    source_texture_count=$(count_regular_files "$texture_dir")

    buildGameShaderDir "$game_key" "$repo_name"
    mkdir -p "$game_dir"
    ln -sfn "$(realpath "$MAIN_PATH/game-shaders/$game_key")" "$game_dir/ReShade_shaders"
    ensureGameIni "$game_dir"

    merged_shader_count=$(count_merged_entries "$MAIN_PATH/game-shaders/$game_key/Merged/Shaders")
    merged_texture_count=$(count_merged_entries "$MAIN_PATH/game-shaders/$game_key/Merged/Textures")

    if [[ -z $shader_dir && -z $texture_dir ]]; then
        result="FAIL"
        reason="no Shaders/Textures directory discovered"
    elif (( merged_shader_count == 0 && merged_texture_count == 0 )); then
        result="FAIL"
        reason="merged output is empty"
    elif [[ ! -L "$game_dir/ReShade_shaders" || ! -f "$game_dir/ReShade.ini" ]]; then
        result="FAIL"
        reason="per-game setup artifacts missing"
    fi

    printf '%s | %s | source_shaders=%s | source_textures=%s | merged_shaders=%s | merged_textures=%s | shader_dir=%s | texture_dir=%s' \
        "$result" \
        "$repo_name" \
        "$source_shader_count" \
        "$source_texture_count" \
        "$merged_shader_count" \
        "$merged_texture_count" \
        "${shader_dir:-<none>}" \
        "${texture_dir:-<none>}"
    [[ -n $reason ]] && printf ' | reason=%s' "$reason"
    printf '\n'

    [[ $result == PASS ]]
}

main() {
    local -a repo_entries=()
    local argument
    local entry
    local repo_name repo_uri repo_branch repo_desc
    local pass_count=0
    local fail_count=0

    AUDIT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/reshade-shader-audit.XXXXXX")"
    if [[ "${SHADER_AUDIT_KEEP_WORKSPACE:-0}" != "1" ]]; then
        trap 'rm -rf "$AUDIT_ROOT"' EXIT
    fi

    prepare_audit_workspace "$AUDIT_ROOT"
    printf 'Shader audit workspace: %s\n' "$AUDIT_ROOT"

    if [[ $# -gt 0 ]]; then
        for argument in "$@"; do
            entry=$(resolve_shader_repo_entry "$argument") || {
                printf 'Unknown shader repo: %s\n' "$argument" >&2
                exit 1
            }
            repo_entries+=("$entry")
        done
    else
        while IFS= read -r entry; do
            repo_entries+=("$entry")
        done < <(list_shader_repo_entries)
    fi

    for entry in "${repo_entries[@]}"; do
        IFS='|' read -r repo_name repo_uri repo_branch repo_desc <<< "$entry"
        if audit_shader_repo "$repo_name" "$repo_uri"; then
            pass_count=$((pass_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done

    printf 'Shader audit summary: %s passed, %s failed.\n' "$pass_count" "$fail_count"
    if [[ $fail_count -eq 0 ]]; then
        printf 'SHADER_AUDIT_RESULT=PASS\n'
        return 0
    fi

    printf 'SHADER_AUDIT_RESULT=FAIL\n'
    return 1
}

main "$@"