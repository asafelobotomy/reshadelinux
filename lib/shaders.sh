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

# Where a pinned clone records the commit this installer last checked out, to tell its own
# checkouts from commits the user made.
function _shaderPinMarker() {
    printf '%s/.git/reshadelinux-pin\n' "$1"
}

# True when HEAD is something this installer put there: the commit it last pinned, or a commit
# upstream has (a clone made before pinning sits on its branch). A commit only the user has is not.
function _shaderCloneHeadIsOurs() {
    local _dir="$1" _head="$2" _marker _recorded=""

    _marker=$(_shaderPinMarker "$_dir")
    [[ -f $_marker ]] && _recorded=$(<"$_marker")
    [[ -n $_recorded && $_recorded == "$_head" ]] && return 0
    [[ -n $(_gitNoPrompt -C "$_dir" for-each-ref --contains "$_head" refs/remotes 2>/dev/null) ]]
}

# Check a clone out at its pinned commit, fetching that one commit when the clone lacks it.
# The clone is left alone, and the call fails, when it holds edits or commits of the user's.
function _checkoutPinnedShaderCommit() {
    local _dir="$1" _commit="$2" _head

    _head=$(_gitNoPrompt -C "$_dir" rev-parse HEAD) || return 1
    [[ $_head == "$_commit" ]] && return 0
    if [[ -n $(_gitNoPrompt -C "$_dir" status --porcelain) ]] || ! _shaderCloneHeadIsOurs "$_dir" "$_head"; then
        printWarn "Not moving $_dir to its pinned commit: it holds local changes. Commit or discard them, or remove the folder."
        return 1
    fi
    if ! _gitNoPrompt -C "$_dir" cat-file -e "$_commit^{commit}" 2>/dev/null; then
        _gitNoPrompt -C "$_dir" fetch --depth 1 origin "$_commit" || return 1
    fi
    _gitNoPrompt -C "$_dir" -c advice.detachedHead=false checkout --quiet --detach "$_commit" || return 1
    printf '%s\n' "$_commit" > "$(_shaderPinMarker "$_dir")"
}

# A clone that was pinned and should now follow its branch (SHADER_REPOS_TRACK_HEAD=1, or the pin
# was removed) is detached; put it back on its branch so a fast-forward can work.
function _reattachShaderClone() {
    local _dir="$1" _branch="$2"

    _gitNoPrompt -C "$_dir" symbolic-ref -q HEAD >/dev/null && return 0
    if [[ -z $_branch ]]; then
        _branch=$(_gitNoPrompt -C "$_dir" for-each-ref --format='%(refname:short)' --count=1 refs/heads) || return 1
    fi
    [[ -n $_branch ]] || return 1
    _gitNoPrompt -C "$_dir" checkout --quiet "$_branch"
}

function _recordFailedShaderRepo() {
    _failedRepos="${_failedRepos:+$_failedRepos,}$1"
}

# Bring one existing clone to what it should be: its pinned commit, or the head of its branch.
function _syncExistingShaderClone() {
    local _dir="$1" _commit="$2" _head

    if [[ -n $_commit ]]; then
        _head=$(_gitNoPrompt -C "$_dir" rev-parse HEAD 2>/dev/null) || _head=""
        [[ $_head == "$_commit" ]] && return 0
        printf '%bMoving shader repo to its pinned commit:%b %s %s\n' "$_GRN" "$_R" "$_shaderRepoUri" "${_commit:0:12}"
        withProgress "Updating shader repo:\n<tt>$_shaderRepoUri</tt>" \
            _checkoutPinnedShaderCommit "$_dir" "$_commit"
        return
    fi
    [[ $UPDATE_RESHADE -eq 1 ]] || return 0
    printf '%bUpdating shader repo:%b %s\n' "$_GRN" "$_R" "$_shaderRepoUri"
    withProgress "Updating shader repo:\n<tt>$_shaderRepoUri</tt>" \
        _reattachAndUpdateShaderClone "$_dir" "$_shaderRepoBranch"
}

function _reattachAndUpdateShaderClone() {
    _reattachShaderClone "$1" "$2" || return 1
    _updateShaderRepoClone "$1"
}

# Clone a pack; a pinned pack is then checked out at its commit, and a clone that cannot reach the
# pin is removed rather than left at an unreviewed commit.
function _cloneShaderRepo() {
    local _dir="$1" _commit="$2"
    local -a _branchArgs=()

    [[ -n $_shaderRepoBranch ]] && _branchArgs=(--branch "$_shaderRepoBranch" --single-branch)
    _gitNoPrompt clone --depth 1 "${_branchArgs[@]}" "$_shaderRepoUri" "$_dir" || return 1
    [[ -n $_commit ]] || return 0
    _checkoutPinnedShaderCommit "$_dir" "$_commit" && return 0
    rm -rf "$_dir"
    return 1
}

# Clone or update selected shader repositories; records failures in _failedRepos.
function ensureSelectedShaderRepos() {
    local _selectedRepos
    _selectedRepos=$(resolveShaderRepoRequirements "$1")
    [[ -z $_selectedRepos ]] && return 0
    _selectedRepos+="${SHADER_CORE_REPOS:+,$SHADER_CORE_REPOS}"
    local _entry _repoDir _commit
    _failedRepos=""

    mkdir -p "$MAIN_PATH/ReShade_shaders" || exit
    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        repoIsSelected "$_selectedRepos" "$_shaderRepoName" || continue
        _repoDir="$MAIN_PATH/ReShade_shaders/$_shaderRepoName"
        _commit=$(shaderRepoWantedCommit "$_shaderRepoUri" "$_shaderRepoBranch") || _commit=""
        if [[ -d $_repoDir ]]; then
            if ! _syncExistingShaderClone "$_repoDir" "$_commit"; then
                printWarn "Could not update shader repo: $_shaderRepoUri"
                _recordFailedShaderRepo "$_shaderRepoName"
            fi
            continue
        fi
        printf '%bCloning shader repo:%b %s\n' "$_GRN" "$_R" "$_shaderRepoUri"
        if ! withProgress "Cloning shader repo:\n<tt>$_shaderRepoUri</tt>" _cloneShaderRepo "$_repoDir" "$_commit"; then
            printWarn "Could not clone shader repo: $_shaderRepoUri"
            _recordFailedShaderRepo "$_shaderRepoName"
        fi
    done < <(listConfiguredShaderRepoEntries)
    [[ -n $_failedRepos ]] && return 1
    return 0
}

# ReShade only searches subfolders of a search path that ends in "\**", and packs keep
# effects in subfolders (SweetFX, CameraFilterPack ...), so an ini written by an older
# version, which named the merged folders without it, hid them. Only lines that are exactly
# what we wrote are changed; a search path list the user edited is left alone. A symlinked
# ini (shared between games) is edited in place, not replaced by a copy.
function _migrateSearchPathsToRecursive() {
    local _ini="$1"

    grep -Eq '^(Effect|Texture)SearchPaths=\.\\ReShade_shaders\\Merged\\(Shaders|Textures)'$'\r''?$' "$_ini" || return 0
    sed -i --follow-symlinks -E 's/^(EffectSearchPaths=\.\\ReShade_shaders\\Merged\\Shaders)(\r?)$/\1\\**\2/;
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
