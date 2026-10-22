#!/bin/bash
# shellcheck disable=SC2317,SC2329  # test functions and stubs are invoked indirectly
# shellcheck disable=SC2034  # variables are set for the code under test
# shellcheck disable=SC2154  # _failedRepos and _shaderRepo* are assigned by the code under test

# Shader packs pinned to a commit, against real local git repositories.

# A bare upstream with commits v1 and v2 of Shaders/marker.fx. Prints the file:// URL; the
# commits are left in _PIN_V1 and _PIN_V2.
_make_two_commit_upstream() {
    local _bare="$TEST_TEMP_DIR/upstream/pack.git" _work="$TEST_TEMP_DIR/upstream/pack.work"

    mkdir -p "$_work/Shaders"
    git init -q --bare -b main "$_bare"
    git init -q -b main "$_work"
    printf 'v1\n' > "$_work/Shaders/marker.fx"
    git -C "$_work" add -A
    git -C "$_work" -c user.name=test -c user.email=test@example.invalid commit -q -m v1
    _PIN_V1=$(git -C "$_work" rev-parse HEAD)
    printf 'v2\n' > "$_work/Shaders/marker.fx"
    git -C "$_work" -c user.name=test -c user.email=test@example.invalid commit -q -am v2
    _PIN_V2=$(git -C "$_work" rev-parse HEAD)
    git -C "$_work" push -q "$_bare" main
    _PIN_URL="file://$_bare"
}

_add_upstream_commit() {
    local _work="$TEST_TEMP_DIR/upstream/pack.work"

    printf '%s\n' "$1" > "$_work/Shaders/marker.fx"
    git -C "$_work" -c user.name=test -c user.email=test@example.invalid commit -q -am "$1"
    git -C "$_work" push -q "$TEST_TEMP_DIR/upstream/pack.git" main
    git -C "$_work" rev-parse HEAD
}

_pin_pack_to() {
    _TEST_PIN_COMMIT="$1"
    listPinnedShaderRepos() { printf '%s - %s\n' "$_PIN_URL" "$_TEST_PIN_COMMIT"; }
}

_prepare_pinning_environment() {
    export SHADER_REPOS="$_PIN_URL|pack||Pack|test pack"
    export SHADER_CORE_REPOS=""
    init_test_runtime_defaults
    UPDATE_RESHADE=1
    withProgress() { shift; "$@"; }
}

_pack_dir() {
    printf '%s/ReShade_shaders/pack\n' "$MAIN_PATH"
}

_pack_marker() {
    cat "$(_pack_dir)/Shaders/marker.fx"
}

test_a_pinned_pack_is_cloned_at_its_pinned_commit() {
    _make_two_commit_upstream
    _prepare_pinning_environment
    _pin_pack_to "$_PIN_V1"

    ensureSelectedShaderRepos pack >/dev/null 2>&1

    [[ $(_pack_marker) == v1 ]]
    [[ $(git -C "$(_pack_dir)" rev-parse HEAD) == "$_PIN_V1" ]]
}

test_a_clone_made_before_pinning_moves_to_the_pin() {
    _make_two_commit_upstream
    _prepare_pinning_environment
    ensureSelectedShaderRepos pack >/dev/null 2>&1
    [[ $(_pack_marker) == v2 ]]

    _pin_pack_to "$_PIN_V1"
    ensureSelectedShaderRepos pack >/dev/null 2>&1

    [[ $(_pack_marker) == v1 ]]
}

test_a_moved_pin_is_fetched_even_when_update_checks_are_off() {
    local _v3

    _make_two_commit_upstream
    _prepare_pinning_environment
    _pin_pack_to "$_PIN_V2"
    ensureSelectedShaderRepos pack >/dev/null 2>&1

    _v3=$(_add_upstream_commit v3)
    _pin_pack_to "$_v3"
    UPDATE_RESHADE=0
    ensureSelectedShaderRepos pack >/dev/null 2>&1

    [[ $(_pack_marker) == v3 ]]
}

test_upstream_commits_after_the_pin_are_not_installed() {
    _make_two_commit_upstream
    _prepare_pinning_environment
    _pin_pack_to "$_PIN_V2"
    ensureSelectedShaderRepos pack >/dev/null 2>&1

    _add_upstream_commit v3 >/dev/null
    ensureSelectedShaderRepos pack >/dev/null 2>&1

    [[ $(_pack_marker) == v2 ]]
}

test_local_edits_keep_a_clone_off_its_new_pin() {
    _make_two_commit_upstream
    _prepare_pinning_environment
    _pin_pack_to "$_PIN_V2"
    ensureSelectedShaderRepos pack >/dev/null 2>&1
    printf 'mine\n' > "$(_pack_dir)/Shaders/marker.fx"

    _pin_pack_to "$_PIN_V1"
    assert_fails ensureSelectedShaderRepos pack
    ensureSelectedShaderRepos pack >/dev/null 2>&1 || true

    [[ $(_pack_marker) == mine ]]
    [[ $_failedRepos == pack ]]
}

test_local_commits_keep_a_clone_off_its_new_pin() {
    local _dir

    _make_two_commit_upstream
    _prepare_pinning_environment
    _pin_pack_to "$_PIN_V2"
    ensureSelectedShaderRepos pack >/dev/null 2>&1
    _dir=$(_pack_dir)
    printf 'mine\n' > "$_dir/Shaders/marker.fx"
    git -C "$_dir" -c user.name=test -c user.email=test@example.invalid commit -q -am mine

    _pin_pack_to "$_PIN_V1"
    ensureSelectedShaderRepos pack >/dev/null 2>&1 || true

    [[ $(_pack_marker) == mine ]]
}

test_a_pin_upstream_does_not_have_leaves_no_clone_behind() {
    _make_two_commit_upstream
    _prepare_pinning_environment
    _pin_pack_to "0123456789abcdef0123456789abcdef01234567"

    ensureSelectedShaderRepos pack >/dev/null 2>&1 || true

    [[ ! -e $(_pack_dir) ]]
    [[ $_failedRepos == pack ]]
}

test_track_head_follows_the_branch_and_reattaches_a_pinned_clone() {
    local _v3

    _make_two_commit_upstream
    _prepare_pinning_environment
    _pin_pack_to "$_PIN_V1"
    ensureSelectedShaderRepos pack >/dev/null 2>&1
    [[ $(_pack_marker) == v1 ]]

    _v3=$(_add_upstream_commit v3)
    SHADER_REPOS_TRACK_HEAD=1
    ensureSelectedShaderRepos pack >/dev/null 2>&1

    [[ $(_pack_marker) == v3 ]]
    git -C "$(_pack_dir)" symbolic-ref -q HEAD >/dev/null
}

test_every_built_in_pack_is_pinned() {
    local _entry _missing=""

    unset SHADER_REPOS
    init_test_runtime_defaults
    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        shaderRepoPinnedCommit "$_shaderRepoUri" "$_shaderRepoBranch" >/dev/null \
            || _missing+=" $_shaderRepoName"
    done < <(listConfiguredShaderRepoEntries)

    if [[ -n $_missing ]]; then
        echo "not pinned (run scripts/release/pin-shader-repos.sh):$_missing" >&2
        return 1
    fi
}

test_a_pin_is_keyed_by_url_and_branch() {
    listPinnedShaderRepos() {
        printf '%s\n' "https://example.invalid/a - 1111111111111111111111111111111111111111" \
            "https://example.invalid/a slim 2222222222222222222222222222222222222222" \
            "https://example.invalid/b - not-a-commit"
    }

    [[ $(shaderRepoPinnedCommit https://example.invalid/a "") == 1111111111111111111111111111111111111111 ]]
    [[ $(shaderRepoPinnedCommit https://example.invalid/a slim) == 2222222222222222222222222222222222222222 ]]
    assert_fails shaderRepoPinnedCommit https://example.invalid/a legacy
    assert_fails shaderRepoPinnedCommit https://example.invalid/b ""
    assert_fails shaderRepoPinnedCommit https://example.invalid/c ""
}

run_pinning_tests() {
    echo -e "${BLUE}Shader Pinning Tests${NC}"
    run_test "A pinned pack is cloned at its commit" test_a_pinned_pack_is_cloned_at_its_pinned_commit
    run_test "A clone made before pinning moves to the pin" test_a_clone_made_before_pinning_moves_to_the_pin
    run_test "A moved pin is fetched with update checks off" test_a_moved_pin_is_fetched_even_when_update_checks_are_off
    run_test "Upstream commits after the pin are not installed" test_upstream_commits_after_the_pin_are_not_installed
    run_test "Local edits keep a clone off its new pin" test_local_edits_keep_a_clone_off_its_new_pin
    run_test "Local commits keep a clone off its new pin" test_local_commits_keep_a_clone_off_its_new_pin
    run_test "An unreachable pin leaves no clone behind" test_a_pin_upstream_does_not_have_leaves_no_clone_behind
    run_test "SHADER_REPOS_TRACK_HEAD follows the branch" test_track_head_follows_the_branch_and_reattaches_a_pinned_clone
    run_test "Every built-in pack is pinned" test_every_built_in_pack_is_pinned
    run_test "A pin is keyed by URL and branch" test_a_pin_is_keyed_by_url_and_branch
    echo ""
}
