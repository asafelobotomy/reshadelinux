#!/bin/bash
# shellcheck disable=SC2317,SC2329  # test functions and stubs are invoked indirectly

# The report the compile check prints from a ReShade.log. The log fixtures are shared with
# compile_check_suite.sh, which tests the script around it.

_CC_REPORT="$REPO_DIR/scripts/diagnostics/helpers/compile_check_report.py"

# A ReShade.log fragment in the shape ReShade 6.8 writes.
_cc_write_log() {
    local _log="$1"

    cat > "$_log" <<'EOF'
00:06:14:400 [  320] | INFO  | Recreated runtime environment on runtime 000000000076A2B0 ('Z:\lab\game\ReShade.ini').
00:06:14:791 [  412] | INFO  | Successfully compiled 'Z:\lab\game\ReShade_shaders\Merged\Shaders\Good.fx' in 0.135000 s.
00:06:15:796 [  420] | WARN  | Successfully compiled 'Z:\lab\game\ReShade_shaders\Merged\Shaders\Sub\Noisy.fx' in 0.286000 s with warnings:
Z:\lab\game\Shader@0x01(59,14-34): warning X3556: integer modulus may be much slower.

00:06:16:100 [  416] | INFO  | Successfully compiled 'Z:\lab\game\ReShade_shaders\Merged\Shaders\Retro Shaders\Resizer.fx' in 0.8 s.
00:06:17:000 [  416] | ERROR | Failed to compile 'Z:\lab\game\ReShade_shaders\Merged\Shaders\Bad.fx':
Z:\lab\game\ReShade_shaders\Merged\Shaders\Common.fxh(54, 15): error X3003: redefinition of 'FOV'
Z:\lab\game\Shader@0x02(9,1): note: see other definition

00:06:18:000 [  416] | INFO  | Exiting ...
EOF
}

_cc_make_effects() {
    local _dir="$1"

    mkdir -p "$_dir/Sub" "$_dir/Retro Shaders"
    : > "$_dir/Good.fx"
    : > "$_dir/Sub/Noisy.fx"
    : > "$_dir/Retro Shaders/Resizer.fx"
    : > "$_dir/Bad.fx"
    : > "$_dir/Common.fxh"
}

test_report_counts_compiled_failed_and_unreported_effects() {
    local _log="$TEST_TEMP_DIR/ReShade.log" _shaders="$TEST_TEMP_DIR/Shaders" _output _status=0

    _cc_write_log "$_log"
    _cc_make_effects "$_shaders"
    : > "$_shaders/Never.fx"

    _output=$(python3 "$_CC_REPORT" "$_log" "$_shaders") || _status=$?

    [[ $_status -eq 1 ]]
    [[ $_output == *"Effects: 5  compiled: 3 (1 with warnings)  failed: 1  not reported: 1"* ]]
    [[ $_output == *"FAIL          Bad.fx | Common.fxh(54, 15): error X3003: redefinition of 'FOV'"* ]]
    [[ $_output == *"NOT REPORTED  Never.fx"* ]]
    [[ $_output == *"COMPILE_CHECK_RESULT=FAIL"* ]]
}

test_report_handles_subfolders_and_folder_names_containing_shaders() {
    local _log="$TEST_TEMP_DIR/ReShade.log" _shaders="$TEST_TEMP_DIR/Shaders" _output

    _cc_write_log "$_log"
    _cc_make_effects "$_shaders"

    _output=$(python3 "$_CC_REPORT" "$_log" "$_shaders") || true

    [[ $_output == *"Effects: 4  compiled: 3"* ]]
    [[ $_output != *"NOT REPORTED"* ]]
}

test_report_passes_when_every_effect_compiled() {
    local _log="$TEST_TEMP_DIR/ReShade.log" _shaders="$TEST_TEMP_DIR/Shaders" _output

    _cc_write_log "$_log"
    _cc_make_effects "$_shaders"
    rm "$_shaders/Bad.fx"
    sed -i "/Failed to compile/,/note: see other/d" "$_log"

    _output=$(python3 "$_CC_REPORT" "$_log" "$_shaders")

    [[ $_output == *"COMPILE_CHECK_RESULT=PASS"* ]]
}

test_report_shortens_compiler_stage_errors() {
    local _log="$TEST_TEMP_DIR/ReShade.log" _shaders="$TEST_TEMP_DIR/Shaders" _output

    mkdir -p "$_shaders"
    : > "$_shaders/Stage.fx"
    cat > "$_log" <<'EOF'
00:06:14:400 [  320] | INFO  | Recreated runtime environment on runtime 0 ('Z:\lab\game\ReShade.ini').
00:06:17:000 [  416] | ERROR | Failed to compile 'Z:\lab\game\ReShade_shaders\Merged\Shaders\Stage.fx':
Z:\lab\game\Shader@0x0000000001D306D0(65,16-92): error X4566: offset texture instructions must take offset in the range -8 to 7

00:06:18:000 [  416] | INFO  | Exiting ...
EOF

    _output=$(python3 "$_CC_REPORT" "$_log" "$_shaders") || true

    [[ $_output == *"Stage.fx | Shader(65,16-92): error X4566"* ]]
    [[ $_output != *"Z:"* ]]
}

test_report_fails_when_the_only_problem_is_an_effect_that_never_reported() {
    local _log="$TEST_TEMP_DIR/ReShade.log" _shaders="$TEST_TEMP_DIR/Shaders" _output _status=0

    _cc_write_log "$_log"
    _cc_make_effects "$_shaders"
    rm "$_shaders/Bad.fx"
    sed -i "/Failed to compile/,/note: see other/d" "$_log"
    : > "$_shaders/Never.fx"

    _output=$(python3 "$_CC_REPORT" "$_log" "$_shaders") || _status=$?

    [[ $_status -eq 1 ]]
    [[ $_output == *"NOT REPORTED  Never.fx"* ]]
    [[ $_output == *"COMPILE_CHECK_RESULT=FAIL"* ]]
}

test_report_treats_known_broken_effects_as_expected_and_flags_ones_that_now_compile() {
    local _log="$TEST_TEMP_DIR/ReShade.log" _shaders="$TEST_TEMP_DIR/Shaders" _output

    _cc_write_log "$_log"
    _cc_make_effects "$_shaders"

    _output=$(python3 "$_CC_REPORT" "$_log" "$_shaders" --known-broken "Bad.fx,Good.fx")

    [[ $_output == *"EXPECTED FAIL Bad.fx"* ]]
    [[ $_output == *"NOW COMPILES  Good.fx"* ]]
    [[ $_output == *"COMPILE_CHECK_RESULT=PASS"* ]]
}

test_report_says_so_when_reshade_never_started() {
    local _log="$TEST_TEMP_DIR/ReShade.log" _shaders="$TEST_TEMP_DIR/Shaders" _output _status=0

    printf '00:00:01:000 [  1] | INFO  | Initializing crosire ReShade version 6.8.0\n' > "$_log"
    _cc_make_effects "$_shaders"

    _output=$(python3 "$_CC_REPORT" "$_log" "$_shaders") || _status=$?

    [[ $_status -eq 2 ]]
    [[ $_output == *"COMPILE_CHECK_RESULT=NO_RUNTIME"* ]]
}

run_compile_check_report_tests() {
    echo -e "${BLUE}Compile Check Report Tests${NC}"
    run_test "Report counts compiled, failed and unreported effects" test_report_counts_compiled_failed_and_unreported_effects
    run_test "Report handles subfolders and folders named Shaders" test_report_handles_subfolders_and_folder_names_containing_shaders
    run_test "Report passes when every effect compiled" test_report_passes_when_every_effect_compiled
    run_test "Report shortens compiler stage errors" test_report_shortens_compiler_stage_errors
    run_test "Report fails on an effect that never reported" test_report_fails_when_the_only_problem_is_an_effect_that_never_reported
    run_test "Report separates known-broken effects" test_report_treats_known_broken_effects_as_expected_and_flags_ones_that_now_compile
    run_test "Report says when ReShade never started" test_report_says_so_when_reshade_never_started
    echo ""
}
