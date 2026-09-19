#!/bin/bash
# shellcheck disable=SC2317,SC2329  # test functions and stubs are invoked indirectly
# shellcheck disable=SC2034  # variables are set for the code under test

# Shader repository clone/update against real local git repositories.

# Create a bare "upstream" repo with one commit that holds $2 in Shaders/marker.fx.
# Prints the file:// URL. The working clone lives beside it so tests can rewrite history.
_make_upstream_repo() {
    local _name="$1" _content="$2"
    local _bare="$TEST_TEMP_DIR/upstream/$_name.git" _work="$TEST_TEMP_DIR/upstream/$_name.work"

    mkdir -p "$_work/Shaders"
    git init -q --bare -b main "$_bare"
    git init -q -b main "$_work"
    printf '%s\n' "$_content" > "$_work/Shaders/marker.fx"
    git -C "$_work" add -A
    git -C "$_work" -c user.name=test -c user.email=test@example.invalid commit -q -m "initial"
    git -C "$_work" push -q "$_bare" main
    printf 'file://%s\n' "$_bare"
}

# Replace the upstream history with an unrelated commit (a force push).
_force_push_new_history() {
    local _name="$1" _content="$2"
    local _bare="$TEST_TEMP_DIR/upstream/$_name.git" _work="$TEST_TEMP_DIR/upstream/$_name.work"

    git -C "$_work" checkout -q --orphan rewritten
    printf '%s\n' "$_content" > "$_work/Shaders/marker.fx"
    git -C "$_work" add -A
    git -C "$_work" -c user.name=test -c user.email=test@example.invalid commit -q -m "rewritten history"
    git -C "$_work" push -q --force "$_bare" rewritten:main
}

_prepare_repo_sync_environment() {
    local _url="$1"

    export SHADER_REPOS="$_url|repo-a||Repo A|test repo"
    init_test_runtime_defaults
    UPDATE_RESHADE=1
    withProgress() { shift; "$@"; }
}

test_shader_repo_clone_then_update_follows_normal_upstream_commits() {
    local _url _before="$PWD"

    _url=$(_make_upstream_repo repo-a "v1")
    _prepare_repo_sync_environment "$_url"

    ensureSelectedShaderRepos "repo-a" >/dev/null 2>&1
    [[ $(<"$MAIN_PATH/ReShade_shaders/repo-a/Shaders/marker.fx") == v1 ]]
    [[ $PWD == "$_before" ]]
}

test_shader_repo_update_recovers_when_upstream_history_was_rewritten() {
    local _url

    _url=$(_make_upstream_repo repo-a "v1")
    _prepare_repo_sync_environment "$_url"
    ensureSelectedShaderRepos "repo-a" >/dev/null 2>&1

    _force_push_new_history repo-a "v2"
    ensureSelectedShaderRepos "repo-a" >/dev/null 2>&1

    [[ -z $_failedRepos ]]
    [[ $(<"$MAIN_PATH/ReShade_shaders/repo-a/Shaders/marker.fx") == v2 ]]
}

test_shader_repo_update_never_discards_local_edits() {
    local _url _status=0

    _url=$(_make_upstream_repo repo-a "v1")
    _prepare_repo_sync_environment "$_url"
    ensureSelectedShaderRepos "repo-a" >/dev/null 2>&1
    printf 'my tweak\n' > "$MAIN_PATH/ReShade_shaders/repo-a/Shaders/marker.fx"

    _force_push_new_history repo-a "v2"
    ensureSelectedShaderRepos "repo-a" >/dev/null 2>&1 || _status=$?

    [[ $_status -ne 0 ]]
    [[ $_failedRepos == repo-a ]]
    [[ $(<"$MAIN_PATH/ReShade_shaders/repo-a/Shaders/marker.fx") == "my tweak" ]]
}

test_shader_repo_sync_runs_git_without_credential_prompts() {
    local _stub="$TEST_TEMP_DIR/git-stub" _log="$TEST_TEMP_DIR/git-env.log"

    mkdir -p "$_stub"
    # shellcheck disable=SC2016  # the single-quoted text is the stub script that gets written
    printf '#!/bin/sh\nprintf "%%s\\n" "${GIT_TERMINAL_PROMPT:-unset}" >> "%s"\nexit 1\n' "$_log" > "$_stub/git"
    chmod +x "$_stub/git"

    _prepare_repo_sync_environment "https://example.invalid/none.git"
    PATH="$_stub:$PATH" ensureSelectedShaderRepos "repo-a" >/dev/null 2>&1 || true

    [[ -s $_log ]]
    assert_fails grep -qv '^0$' "$_log"
}

run_repo_sync_tests() {
    echo -e "${BLUE}Shader Repository Sync Tests${NC}"
    run_test "Clone follows the upstream branch" test_shader_repo_clone_then_update_follows_normal_upstream_commits
    run_test "Update recovers from rewritten upstream history" test_shader_repo_update_recovers_when_upstream_history_was_rewritten
    run_test "Update never discards local edits" test_shader_repo_update_never_discards_local_edits
    run_test "Sync runs git without credential prompts" test_shader_repo_sync_runs_git_without_credential_prompts
    echo ""
}
