#!/bin/bash
# shellcheck disable=SC2317,SC2329  # test functions and stubs are invoked indirectly
# shellcheck disable=SC2034  # variables are set for the code under test
# shellcheck disable=SC2154  # variables are assigned by the code under test

# Packs that need other packs (headers or effects), the always-present core headers, and
# effects that never compile.

_registry_entry() {
    # <name> [requires]
    printf 'https://example.com/%s|%s||%s|desc of %s|%s' "$1" "$1" "$1" "$1" "${2:-}"
}

_use_registry() {
    local _joined="" _entry
    for _entry in "$@"; do
        _joined+="${_joined:+;}$_entry"
    done
    export SHADER_REPOS="$_joined"
}

test_registry_entry_exposes_its_requirements() {
    parseShaderRepoEntry "https://example.com/a|alpha||Alpha|desc|beta,gamma"
    [[ $_shaderRepoRequires == "beta,gamma" ]]
    [[ $_shaderRepoDesc == "desc" ]]
}

test_registry_entry_without_requirements_clears_the_previous_value() {
    parseShaderRepoEntry "https://example.com/a|alpha||Alpha|desc|beta"
    parseShaderRepoEntry "https://example.com/b|bravo||Bravo|desc"
    [[ -z $_shaderRepoRequires ]]
}

test_requirements_are_added_transitively_without_duplicates() {
    _use_registry "$(_registry_entry alpha beta)" "$(_registry_entry beta gamma)" \
        "$(_registry_entry gamma)" "$(_registry_entry delta)"

    [[ $(resolveShaderRepoRequirements "alpha") == "alpha,beta,gamma" ]]
    [[ $(resolveShaderRepoRequirements "alpha,gamma") == "alpha,gamma,beta" ]]
    [[ $(resolveShaderRepoRequirements "delta") == "delta" ]]
}

test_requirement_cycles_and_unknown_names_are_harmless() {
    _use_registry "$(_registry_entry alpha beta)" "$(_registry_entry beta alpha,missing)"

    [[ $(resolveShaderRepoRequirements "alpha") == "alpha,beta" ]]
}

test_resolving_nothing_prints_nothing() {
    _use_registry "$(_registry_entry alpha beta)" "$(_registry_entry beta)"

    [[ -z $(resolveShaderRepoRequirements "") ]]
}

test_default_registry_requirements_name_known_packs() {
    local _entry _name _required
    local -A _known=()

    unset SHADER_REPOS
    init_test_runtime_defaults
    while IFS= read -r _entry; do
        parseShaderRepoEntry "$_entry"
        _known["$_shaderRepoName"]=1
    done < <(listConfiguredShaderRepoEntries)

    while IFS= read -r _entry; do
        parseShaderRepoEntry "$_entry"
        [[ -n $_shaderRepoRequires ]] || continue
        for _required in ${_shaderRepoRequires//,/ }; do
            [[ -n ${_known["$_required"]+x} ]] || { echo "$_shaderRepoName requires unknown $_required" >&2; return 1; }
            [[ $_required != "$_shaderRepoName" ]] || { echo "$_shaderRepoName requires itself" >&2; return 1; }
        done
    done < <(listConfiguredShaderRepoEntries)
    [[ -n ${_known["$SHADER_CORE_REPOS"]+x} ]]
}

test_default_registry_declares_the_known_pack_dependencies() {
    unset SHADER_REPOS
    init_test_runtime_defaults

    [[ $(resolveShaderRepoRequirements "ann-reshade") == *cshade* ]]
    [[ $(resolveShaderRepoRequirements "bfbfx-shaders") == *zenteon-fx* ]]
    [[ $(resolveShaderRepoRequirements "reshade-tfaa") == *immerse-shaders* ]]
    [[ $(resolveShaderRepoRequirements "jakobpcoder-shades") == *immerse-shaders* ]]
    [[ $(resolveShaderRepoRequirements "optical-flow") == *quintfx* ]]
    [[ $(resolveShaderRepoRequirements "lordbean-shaders") == *sweetfx-shaders* ]]
}

test_build_merges_the_effects_of_a_required_pack() {
    _use_registry "$(_registry_entry alpha beta)" "$(_registry_entry beta)" "$(_registry_entry other)"
    create_mock_shader_repo "alpha"
    create_mock_shader_repo "beta"
    create_mock_shader_repo "other"

    buildGameShaderDir "84001" "alpha"

    [[ -L "$MAIN_PATH/game-shaders/84001/Merged/Shaders/alpha.fx" ]]
    [[ -L "$MAIN_PATH/game-shaders/84001/Merged/Shaders/beta.fx" ]]
    [[ ! -e "$MAIN_PATH/game-shaders/84001/Merged/Shaders/other.fx" ]]
}

test_build_tolerates_a_required_pack_that_is_not_installed() {
    _use_registry "$(_registry_entry alpha beta)" "$(_registry_entry beta)"
    create_mock_shader_repo "alpha"

    buildGameShaderDir "84002" "alpha"

    [[ -L "$MAIN_PATH/game-shaders/84002/Merged/Shaders/alpha.fx" ]]
}

# Clone tests use real local repositories, as repos_suite.sh does.
_make_pack_upstream() {
    local _name="$1" _bare="$TEST_TEMP_DIR/upstream/$1.git" _work="$TEST_TEMP_DIR/upstream/$1.work"

    mkdir -p "$_work/Shaders"
    git init -q --bare -b main "$_bare"
    git init -q -b main "$_work"
    echo "// effect $_name" > "$_work/Shaders/$_name.fx"
    echo "// header $_name" > "$_work/Shaders/$_name.fxh"
    git -C "$_work" add -A
    git -C "$_work" -c user.name=test -c user.email=test@example.invalid commit -q -m initial
    git -C "$_work" push -q "$_bare" main
    printf 'file://%s' "$_bare"
}

_prepare_clone_environment() {
    init_test_runtime_defaults
    UPDATE_RESHADE=0
    withProgress() { shift; "$@"; }
    export SHADER_CORE_REPOS="core-pack"
}

test_ensure_clones_required_packs_and_the_core_pack() {
    local _core _alpha _beta _other

    _core=$(_make_pack_upstream core-pack)
    _alpha=$(_make_pack_upstream alpha)
    _beta=$(_make_pack_upstream beta)
    _other=$(_make_pack_upstream other)
    export SHADER_REPOS="$_core|core-pack||Core|core;$_alpha|alpha||Alpha|a|beta;$_beta|beta||Beta|b;$_other|other||Other|o"
    _prepare_clone_environment

    ensureSelectedShaderRepos "alpha" >/dev/null 2>&1

    [[ -d "$MAIN_PATH/ReShade_shaders/alpha" ]]
    [[ -d "$MAIN_PATH/ReShade_shaders/beta" ]]
    [[ -d "$MAIN_PATH/ReShade_shaders/core-pack" ]]
    [[ ! -d "$MAIN_PATH/ReShade_shaders/other" ]]
}

test_ensure_clones_nothing_for_an_empty_selection() {
    local _core

    _core=$(_make_pack_upstream core-pack)
    export SHADER_REPOS="$_core|core-pack||Core|core"
    _prepare_clone_environment

    ensureSelectedShaderRepos "" >/dev/null 2>&1

    [[ ! -d "$MAIN_PATH/ReShade_shaders/core-pack" ]]
}

test_core_headers_are_linked_but_core_effects_are_not_merged() {
    local _core _alpha

    _core=$(_make_pack_upstream core-pack)
    _alpha=$(_make_pack_upstream alpha)
    export SHADER_REPOS="$_core|core-pack||Core|core;$_alpha|alpha||Alpha|a"
    _prepare_clone_environment

    ensureSelectedShaderRepos "alpha" >/dev/null 2>&1
    buildGameShaderDir "84003" "alpha"

    [[ -L "$MAIN_PATH/game-shaders/84003/Merged/Shaders/alpha.fx" ]]
    [[ -L "$MAIN_PATH/game-shaders/84003/Merged/Shaders/core-pack.fxh" ]]
    [[ ! -e "$MAIN_PATH/game-shaders/84003/Merged/Shaders/core-pack.fx" ]]
}

test_failed_requirement_clone_is_reported_for_retry() {
    local _alpha _status=0

    _alpha=$(_make_pack_upstream alpha)
    export SHADER_REPOS="$_alpha|alpha||Alpha|a|beta;file://$TEST_TEMP_DIR/upstream/nope.git|beta||Beta|b"
    _prepare_clone_environment

    ensureSelectedShaderRepos "alpha" >/dev/null 2>&1 || _status=$?

    [[ $_status -ne 0 ]]
    [[ $_failedRepos == *beta* ]]
}

# ---- effects that never compile ----

_effect_repo() {
    local _name="$1"; shift
    local _root="$MAIN_PATH/ReShade_shaders/$_name/Shaders" _file

    mkdir -p "$_root"
    for _file in "$@"; do
        mkdir -p "$_root/$(dirname "$_file")"
        echo "// $_file" > "$_root/$_file"
    done
}

test_broken_effects_are_removed_from_every_build() {
    export SHADER_REPOS="https://example.com/a|alpha"
    export SHADER_BROKEN_EFFECTS="Bad.fx,Sub/Worse.fx"
    _effect_repo alpha Good.fx Bad.fx Sub/Worse.fx Sub/Fine.fx

    buildGameShaderDir "85001" "alpha"

    local _shaders="$MAIN_PATH/game-shaders/85001/Merged/Shaders"
    [[ -L "$_shaders/Good.fx" ]]
    [[ -L "$_shaders/Sub/Fine.fx" ]]
    [[ ! -e "$_shaders/Bad.fx" ]]
    [[ ! -e "$_shaders/Sub/Worse.fx" ]]
}

test_an_empty_broken_effect_list_keeps_everything() {
    export SHADER_REPOS="https://example.com/a|alpha"
    export SHADER_BROKEN_EFFECTS=""
    _effect_repo alpha Bad.fx

    buildGameShaderDir "85003" "alpha"

    [[ -L "$MAIN_PATH/game-shaders/85003/Merged/Shaders/Bad.fx" ]]
}

test_default_broken_effect_list_matches_the_proton_compile_results() {
    local _effect

    unset SHADER_BROKEN_EFFECTS
    init_test_runtime_defaults

    for _effect in GrainSpread.fx NTSCCustom.fx NTSC_XOT.fx BX_XIV_ChromakeyPlus.fx \
        TrooCullers.fx CameraFilterPack/OilPaint.fx ZenWork.fx; do
        [[ ,$SHADER_BROKEN_EFFECTS, == *",$_effect,"* ]] || { echo "missing $_effect" >&2; return 1; }
    done
}

test_broken_effects_do_not_hide_app_specific_excludes() {
    export SHADER_REPOS="https://example.com/a|alpha"
    export SHADER_BROKEN_EFFECTS="Bad.fx"
    export SHADER_EFFECT_EXCLUDES="424242|Other.fx"
    _effect_repo alpha Bad.fx Other.fx Keep.fx

    buildGameShaderDir "85004" "alpha" "424242"

    local _shaders="$MAIN_PATH/game-shaders/85004/Merged/Shaders"
    [[ ! -e "$_shaders/Bad.fx" ]]
    [[ ! -e "$_shaders/Other.fx" ]]
    [[ -L "$_shaders/Keep.fx" ]]
}

run_shader_requirements_tests() {
    echo -e "${BLUE}Shader Requirements and Exclusion Tests${NC}"
    run_test "Registry entry exposes its requirements" test_registry_entry_exposes_its_requirements
    run_test "Registry entry without requirements clears the value" test_registry_entry_without_requirements_clears_the_previous_value
    run_test "Requirements resolve transitively" test_requirements_are_added_transitively_without_duplicates
    run_test "Requirement cycles and unknown names are harmless" test_requirement_cycles_and_unknown_names_are_harmless
    run_test "Resolving nothing prints nothing" test_resolving_nothing_prints_nothing
    run_test "Default requirements name known packs" test_default_registry_requirements_name_known_packs
    run_test "Default registry declares the known dependencies" test_default_registry_declares_the_known_pack_dependencies
    run_test "Build merges a required pack" test_build_merges_the_effects_of_a_required_pack
    run_test "Build tolerates a required pack that is missing" test_build_tolerates_a_required_pack_that_is_not_installed
    run_test "Ensure clones required packs and the core pack" test_ensure_clones_required_packs_and_the_core_pack
    run_test "Ensure clones nothing for an empty selection" test_ensure_clones_nothing_for_an_empty_selection
    run_test "Core headers are linked without core effects" test_core_headers_are_linked_but_core_effects_are_not_merged
    run_test "Failed requirement clone is reported" test_failed_requirement_clone_is_reported_for_retry
    run_test "Broken effects are removed from every build" test_broken_effects_are_removed_from_every_build
    run_test "Empty broken effect list keeps everything" test_an_empty_broken_effect_list_keeps_everything
    run_test "Default broken effect list matches the compile results" test_default_broken_effect_list_matches_the_proton_compile_results
    run_test "Broken effects keep app-specific excludes working" test_broken_effects_do_not_hide_app_specific_excludes
    echo ""
}
