# shellcheck shell=bash
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck disable=SC2154  # _shaderRepo* are set by parseShaderRepoEntry in shader_registry.sh

# Shader repository sync, per-game ini/preset files, and the selection UI.

# Run git without ever asking for credentials (a repository that was renamed or made
# private would otherwise block on a prompt) and give up on a stalled connection.
function _gitNoPrompt() {
    GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 "$@"
}

# Fast-forward a managed shader clone. When upstream history was rewritten a
# fast-forward can never succeed, so re-sync to upstream instead, but only when the
# clone holds nothing of the user's: no local commits, edits or untracked files.
# The local commits are counted before `pull`, because pull fetches first and moves
# the remote-tracking ref, after which the comparison would be meaningless.
function _updateShaderRepoClone() {
    local _dir="$1" _knownUpstream _localCommits

    _knownUpstream=$(_gitNoPrompt -C "$_dir" rev-parse '@{upstream}') || return 1
    _localCommits=$(_gitNoPrompt -C "$_dir" rev-list --count "$_knownUpstream..HEAD") || return 1

    _gitNoPrompt -C "$_dir" pull --ff-only && return 0
    [[ $_localCommits -eq 0 ]] || return 1
    [[ -z $(_gitNoPrompt -C "$_dir" status --porcelain) ]] || return 1
    _gitNoPrompt -C "$_dir" fetch --depth 1 || return 1
    _gitNoPrompt -C "$_dir" reset --hard '@{upstream}'
}

# Clone or update selected shader repositories; records failures in _failedRepos.
function ensureSelectedShaderRepos() {
    local _selectedRepos
    _selectedRepos=$(resolveShaderRepoRequirements "$1")
    [[ -z $_selectedRepos ]] && return 0
    _selectedRepos+="${SHADER_CORE_REPOS:+,$SHADER_CORE_REPOS}"
    local _entry _status _repoDir
    _failedRepos=""

    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        repoIsSelected "$_selectedRepos" "$_shaderRepoName" || continue
        _repoDir="$MAIN_PATH/ReShade_shaders/$_shaderRepoName"
        if [[ -d $_repoDir ]]; then
            if [[ $UPDATE_RESHADE -eq 1 ]]; then
                printf '%bUpdating shader repo:%b %s\n' "$_GRN" "$_R" "$_shaderRepoUri"
                withProgress "Updating shader repo:\n<tt>$_shaderRepoUri</tt>" \
                    _updateShaderRepoClone "$_repoDir"
                _status=$?
                if [[ $_status -ne 0 ]]; then
                    printf '%bCould not update shader repo: %s%b\n' "$_YLW" "$_shaderRepoUri" "$_R"
                    _failedRepos="${_failedRepos:+$_failedRepos,}$_shaderRepoName"
                fi
            fi
        else
            mkdir -p "$MAIN_PATH/ReShade_shaders" || exit
            local branchArgs=()
            [[ -n $_shaderRepoBranch ]] && branchArgs=(--branch "$_shaderRepoBranch" --single-branch)
            printf '%bCloning shader repo:%b %s\n' "$_GRN" "$_R" "$_shaderRepoUri"
            withProgress "Cloning shader repo:\n<tt>$_shaderRepoUri</tt>" \
                _gitNoPrompt clone --depth 1 "${branchArgs[@]}" "$_shaderRepoUri" "$_repoDir"
            _status=$?
            if [[ $_status -ne 0 ]]; then
                printf '%bCould not clone shader repo: %s%b\n' "$_YLW" "$_shaderRepoUri" "$_R"
                _failedRepos="${_failedRepos:+$_failedRepos,}$_shaderRepoName"
            fi
        fi
    done < <(listConfiguredShaderRepoEntries)
    [[ -n $_failedRepos ]] && return 1
    return 0
}

# ReShade only searches subfolders of a search path that ends in "\**", and packs keep
# effects in subfolders (SweetFX, CameraFilterPack ...), so an ini written by an older
# version, which named the merged folders without it, hid them. Only lines that are exactly
# what we wrote are changed; a search path list the user edited is left alone.
function _migrateSearchPathsToRecursive() {
    local _ini="$1"

    grep -Eq '^(Effect|Texture)SearchPaths=\.\\ReShade_shaders\\Merged\\(Shaders|Textures)'$'\r''?$' "$_ini" || return 0
    sed -i -E 's/^(EffectSearchPaths=\.\\ReShade_shaders\\Merged\\Shaders)(\r?)$/\1\\**\2/;
        s/^(TextureSearchPaths=\.\\ReShade_shaders\\Merged\\Textures)(\r?)$/\1\\**\2/' "$_ini" \
        || logDebug "Could not migrate the search paths in $_ini"
}

# Create a per-game ReShade.ini when needed.
function ensureGameIni() {
    local _gamePath="$1"
    [[ $GLOBAL_INI == 0 ]] && return 0
    local _target="$_gamePath/ReShade.ini"
    if [[ -f $_target ]]; then
        _migrateSearchPathsToRecursive "$_target"
        return 0
    fi
    if [[ $GLOBAL_INI == ReShade.ini ]]; then
        cat > "$_target" <<'EOF'
[GENERAL]
EffectSearchPaths=.\ReShade_shaders\Merged\Shaders\**
TextureSearchPaths=.\ReShade_shaders\Merged\Textures\**
EOF
        return 0
    fi
    [[ -f "$MAIN_PATH/$GLOBAL_INI" ]] || return 1
    cp "$MAIN_PATH/$GLOBAL_INI" "$_target"
}

# Copy the configured preset into the game directory when needed.
function ensureGamePreset() {
    local _gamePath="$1"
    [[ -z $LINK_PRESET ]] && return 0
    [[ -f "$MAIN_PATH/$LINK_PRESET" ]] || return 0
    [[ -f "$_gamePath/$LINK_PRESET" ]] && return 0
    cp "$MAIN_PATH/$LINK_PRESET" "$_gamePath/$LINK_PRESET"
}

# Show the shader repository selection UI and print the chosen repo names.
function selectShaders() {
    local _current="$1"
    local -a _names=() _labels=() _rows=()
    if [[ ${UI_AUTO_CONFIRM:-0} == 1 && $_UI_BACKEND != cli && -z $_current ]]; then
        _current=$(getDefaultSelectedRepos)
    fi
    local _entry _checked _rowKey
    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        _checked="$(repoChecklistState "$_current" "$_shaderRepoName")"
        _names+=("$_shaderRepoName")
        _labels+=("$(formatShaderRepoDisplayLabel "$_shaderRepoUri" "$_shaderRepoTitle" "$_shaderRepoDesc")")
        _rowKey="${#_names[@]}"
        _rows+=("$_rowKey" "${_labels[-1]}" "$_checked")
    done < <(listConfiguredShaderRepoEntries)
    local -a _selected_names=()
    if [[ $_UI_BACKEND != cli ]]; then
        local _term_lines _list_h _box_h
        _term_lines=$(tput lines 2>/dev/null || echo 24)
        _list_h=$(( _term_lines - 10 ))
        (( _list_h < 5 )) && _list_h=5
        (( _list_h > ${#_names[@]} )) && _list_h=${#_names[@]}
        _box_h=$(( _list_h + 8 ))
        local _result
        _result=$(ui_checklist "ReShade - Shader Repositories" \
            "Select which shader repositories to install for this game. Each entry shows the pack title, creator, and a short highlight summary." \
            "$_box_h" 100 "$_list_h" "${_rows[@]}") || return 1
        _result=${_result//\"/}
        if [[ -n $_result ]]; then
            local _selected_index
            while IFS= read -r _selected_index || [[ -n $_selected_index ]]; do
                [[ $_selected_index =~ ^[0-9]+$ ]] || continue
                _selected_names+=("${_names[$((_selected_index - 1))]}")
            done < <(printf '%s' "$_result" | tr '|\n\r\t ' '\n' | sed '/^$/d')
        fi
    else
        printf '%bSelect shader repositories to install for this game:%b\n' "$_CYN" "$_R" >&2
        local _i _ans
        for (( _i=0; _i<${#_names[@]}; _i++ )); do
            local _def="y"
            [[ "${_rows[$(( (_i * 3) + 2 ))]}" == "OFF" ]] && _def="n"
            printf '  [%s] %s\n     Include? [%s]: ' \
                "$(( _i + 1 ))" "${_labels[$_i]}" "$_def" >&2
            read -r _ans
            [[ -z $_ans ]] && _ans="$_def"
            [[ "$_ans" =~ ^(y|Y|yes|YES)$ ]] && _selected_names+=("${_names[$_i]}")
        done
    fi
    local IFS=','
    echo "${_selected_names[*]}"
}
