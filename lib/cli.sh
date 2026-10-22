# shellcheck shell=bash
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck disable=SC2154  # _shaderRepo* are set by parseShaderRepoEntry in shader_registry.sh

PROJECT_URL="https://github.com/asafelobotomy/reshadelinux"

function printUsage() {
    printf 'Usage: %s [options]\n\n' "$0"
    printf 'Install, update or remove ReShade for Wine and Proton games.\n\n'
    printf 'Examples:\n'
    printf '  %s                                     Pick a game and install interactively.\n' "$0"
    printf '  %s --cli --app-id=255710 --shader-repos=all\n' "$0"
    printf '  %s --no-input --game-path=~/Games/MyGame --dll-override=d3d9\n' "$0"
    printf '  %s --update-all --quiet                 Re-link every tracked game, print only problems.\n' "$0"
    printf '  %s --dry-run --update-all               Show what --update-all would change.\n' "$0"
    printf '  %s --list-shader-repos --json           Print the shader registry as JSON.\n\n' "$0"
    printf 'Options:\n'
    printf '  --update-all              Re-link ReShade for all previously installed games.\n'
    printf '  --uninstall               Remove ReShade from the game chosen with --game-path or --app-id.\n'
    printf '  --cli                     Force the plain CLI backend.\n'
    printf '  --ui-backend=<backend>    Force auto, yad, whiptail, dialog, or cli.\n'
    printf '  --game-path=<path>        Use an explicit game directory or .exe path.\n'
    printf '  --app-id=<appid>          Select a detected Steam game by App ID, or persist it with --game-path.\n'
    printf '  --dll-override=<name>     Use an explicit ReShade DLL override, e.g. dxgi or d3d9.\n'
    printf '  --shader-repos=<value>    Use all, none, or a comma-separated repo list. With --update-all, override the tracked repos for every game in the batch.\n'
    printf '  --list-shader-repos       Print the configured shader repo names and labels.\n'
    printf '  --json                    With --list-shader-repos, print JSON instead of text.\n'
    printf '  --no-input                Never prompt: use the flags, stored settings and detected defaults, and fail when something is missing. Implies --cli.\n'
    printf '  --dry-run, -n             Show what would be downloaded, linked and written, and change nothing.\n'
    printf '  --quiet, -q               Print only warnings, errors and the launch option.\n'
    printf '  --version, -V             Show the script version.\n'
    printf '  --help, -h                Show this help message.\n\n'
    printf 'Exit status: 0 success, 1 failure, 2 usage, 3 missing program, 4 network, 5 integrity check.\n'
    printf 'Documentation and source: %s\n' "$PROJECT_URL"
}

function printCliVersion() {
    printf '%s\n' "${SCRIPT_VERSION:-unknown}"
}

function printAvailableShaderRepos() {
    local _entry _label

    printf 'Configured shader repositories:\n'
    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        _label=$(formatShaderRepoDisplayLabel "$_shaderRepoUri" "$_shaderRepoTitle" "$_shaderRepoDesc")
        printf '  %s\t%s\n' "$_shaderRepoName" "$_label"
    done < <(listConfiguredShaderRepoEntries)
}

# A JSON string literal. Registry text is plain, but a SHADER_REPOS override can hold anything.
function _jsonString() {
    local _s="$1" _out="" _c _i
    _s=${_s//\\/\\\\}
    _s=${_s//\"/\\\"}
    _s=${_s//$'\n'/\\n}
    _s=${_s//$'\r'/\\r}
    _s=${_s//$'\t'/\\t}
    if [[ $_s != *[[:cntrl:]]* ]]; then
        printf '"%s"' "$_s"
        return
    fi
    for (( _i = 0; _i < ${#_s}; _i++ )); do
        _c="${_s:_i:1}"
        if [[ $_c == [[:cntrl:]] ]]; then
            printf -v _c '\\u%04x' "'$_c"
        fi
        _out+="$_c"
    done
    printf '"%s"' "$_out"
}

function _jsonStringArray() {
    local _list="$1" _item _sep=""
    local -a _items=()

    IFS=',' read -ra _items <<< "$_list"
    printf '['
    for _item in "${_items[@]}"; do
        [[ -n $_item ]] || continue
        printf '%s%s' "$_sep" "$(_jsonString "$_item")"
        _sep=","
    done
    printf ']'
}

function printAvailableShaderReposJson() {
    local _entry _sep="" _commit _commitJson

    printf '[\n'
    while IFS= read -r _entry || [[ -n $_entry ]]; do
        parseShaderRepoEntry "$_entry"
        _commit=$(shaderRepoPinnedCommit "$_shaderRepoUri" "$_shaderRepoBranch") || _commit=""
        _commitJson=null
        [[ -n $_commit ]] && _commitJson=$(_jsonString "$_commit")
        printf '%s  {"name":%s,"uri":%s,"branch":%s,"title":%s,"description":%s,"creator":%s,"requires":%s,"commit":%s}' \
            "$_sep" \
            "$(_jsonString "$_shaderRepoName")" \
            "$(_jsonString "$_shaderRepoUri")" \
            "$(_jsonString "$_shaderRepoBranch")" \
            "$(_jsonString "$_shaderRepoTitle")" \
            "$(_jsonString "$_shaderRepoDesc")" \
            "$(_jsonString "$(getShaderRepoCreator "$_shaderRepoUri")")" \
            "$(_jsonStringArray "$_shaderRepoRequires")" \
            "$_commitJson"
        _sep=$',\n'
    done < <(listConfiguredShaderRepoEntries)
    printf '\n]\n'
}

function handleCliInfoArgs() {
    if [[ ${CLI_LIST_SHADER_REPOS:-0} -eq 1 ]]; then
        if [[ ${CLI_JSON:-0} -eq 1 ]]; then
            printAvailableShaderReposJson >&"${_RESULT_FD:-1}"
        else
            printAvailableShaderRepos >&"${_RESULT_FD:-1}"
        fi
        exit 0
    fi
}

function _cliUsageError() {
    printf 'Unknown argument: %s\n\n' "$1" >&2
    printUsage >&2
    exit "$EXIT_USAGE"
}

function parseCliArgs() {
    _BATCH_UPDATE=0
    CLI_UNINSTALL=0
    CLI_FORCE_CLI_SET=0
    CLI_UI_BACKEND_SET=0
    CLI_GAME_PATH=""
    CLI_GAME_PATH_SET=0
    CLI_APP_ID=""
    CLI_APP_ID_SET=0
    CLI_DLL_OVERRIDE=""
    CLI_DLL_OVERRIDE_SET=0
    CLI_SHADER_REPOS=""
    CLI_SHADER_REPOS_SET=0
    CLI_LIST_SHADER_REPOS=0
    CLI_JSON=0
    CLI_NO_INPUT=0
    CLI_DRY_RUN=0
    CLI_QUIET=0

    local _arg
    for _arg in "$@"; do
        # shellcheck disable=SC2034  # CLI_QUIET is read by the entrypoint
        case "$_arg" in
            --update-all) _BATCH_UPDATE=1 ;;
            --uninstall) CLI_UNINSTALL=1 ;;
            --cli)
                UI_BACKEND=cli
                CLI_FORCE_CLI_SET=1
                ;;
            --ui-backend=*)
                UI_BACKEND="$(_trim_cli_value "${_arg#*=}")"
                UI_BACKEND="${UI_BACKEND,,}"
                CLI_UI_BACKEND_SET=1
                ;;
            --game-path=*)
                CLI_GAME_PATH="${_arg#*=}"
                CLI_GAME_PATH_SET=1
                ;;
            --app-id=*)
                CLI_APP_ID="${_arg#*=}"
                CLI_APP_ID_SET=1
                ;;
            --dll-override=*)
                CLI_DLL_OVERRIDE="${_arg#*=}"
                CLI_DLL_OVERRIDE_SET=1
                ;;
            --shader-repos=*)
                CLI_SHADER_REPOS="${_arg#*=}"
                CLI_SHADER_REPOS_SET=1
                ;;
            --list-shader-repos) CLI_LIST_SHADER_REPOS=1 ;;
            --json) CLI_JSON=1 ;;
            --no-input) CLI_NO_INPUT=1 ;;
            --dry-run|-n) CLI_DRY_RUN=1 ;;
            --quiet|-q) CLI_QUIET=1 ;;
            --version|-V)
                printCliVersion
                exit 0
                ;;
            --help|-h)
                printUsage
                exit 0
                ;;
            *) _cliUsageError "$_arg" ;;
        esac
    done

    # Prompts would block a script, so --no-input runs without dialogs. Decided here, before
    # init_runtime_config picks a backend; an explicit non-CLI backend is rejected in validateCliArgs.
    if [[ $CLI_NO_INPUT -eq 1 && $CLI_UI_BACKEND_SET -eq 0 ]]; then
        UI_BACKEND=cli
    fi
}

function _trim_cli_value() {
    local _value="$1"
    _value="${_value#"${_value%%[![:space:]]*}"}"
    _value="${_value%"${_value##*[![:space:]]}"}"
    printf '%s\n' "$_value"
}

function _usageError() {
    failWith "$EXIT_USAGE" "$@"
}

function validateCliArgs() {
    if [[ ${CLI_FORCE_CLI_SET:-0} -eq 1 && ${CLI_UI_BACKEND_SET:-0} -eq 1 ]]; then
        _usageError "Use either --cli or --ui-backend=<backend>, not both."
    fi

    if [[ ${CLI_NO_INPUT:-0} -eq 1 && ${CLI_UI_BACKEND_SET:-0} -eq 1 && ${UI_BACKEND:-} != cli ]]; then
        _usageError "--no-input never opens dialogs, so it cannot be combined with --ui-backend=$UI_BACKEND."
    fi

    if [[ ${CLI_JSON:-0} -eq 1 && ${CLI_LIST_SHADER_REPOS:-0} -eq 0 ]]; then
        _usageError "--json only applies to --list-shader-repos."
    fi

    if [[ $_BATCH_UPDATE -eq 1 ]]; then
        if [[ ${CLI_GAME_PATH_SET:-0} -eq 1 || ${CLI_APP_ID_SET:-0} -eq 1 || ${CLI_DLL_OVERRIDE_SET:-0} -eq 1 ]]; then
            _usageError "--update-all cannot be combined with --game-path, --app-id, or --dll-override. Use --shader-repos if you need to override shader selection for every tracked game."
        fi
        [[ ${CLI_UNINSTALL:-0} -eq 0 ]] || _usageError "Use either --update-all or --uninstall, not both."
    fi

    if [[ ${CLI_UNINSTALL:-0} -eq 1 ]]; then
        if [[ ${CLI_DLL_OVERRIDE_SET:-0} -eq 1 || ${CLI_SHADER_REPOS_SET:-0} -eq 1 ]]; then
            _usageError "--uninstall removes every ReShade file, so --dll-override and --shader-repos do not apply."
        fi
    fi

    if [[ ${CLI_GAME_PATH_SET:-0} -eq 1 ]]; then
        CLI_GAME_PATH="$(_trim_cli_value "$CLI_GAME_PATH")"
    fi

    if [[ ${CLI_APP_ID_SET:-0} -eq 1 ]]; then
        CLI_APP_ID="$(_trim_cli_value "$CLI_APP_ID")"
        [[ $CLI_APP_ID =~ ^[0-9]+$ ]] || _usageError "The App ID supplied via --app-id must be numeric."
    fi

    if [[ ${CLI_DLL_OVERRIDE_SET:-0} -eq 1 ]]; then
        CLI_DLL_OVERRIDE="$(_trim_cli_value "$CLI_DLL_OVERRIDE")"
        CLI_DLL_OVERRIDE="${CLI_DLL_OVERRIDE,,}"
        CLI_DLL_OVERRIDE="${CLI_DLL_OVERRIDE%.dll}"
        isKnownDllOverride "$CLI_DLL_OVERRIDE" || _usageError "Unknown DLL override '$CLI_DLL_OVERRIDE'. Expected one of: $COMMON_OVERRIDES"
    fi

    if [[ ${CLI_SHADER_REPOS_SET:-0} -eq 1 ]]; then
        CLI_SHADER_REPOS=$(normalizeRequestedShaderRepos "$CLI_SHADER_REPOS") || _usageError "Invalid value supplied via --shader-repos. Use all, none, or a comma-separated list of configured repo names."
    fi
}

# Called where the program would otherwise ask the user something. Under --no-input there is
# nobody to ask, so stop and say which flag supplies the answer.
function requireInput() {
    [[ ${CLI_NO_INPUT:-0} -eq 1 ]] || return 0
    _usageError "--no-input: $1"
}

function isNoInput() {
    [[ ${CLI_NO_INPUT:-0} -eq 1 ]]
}

function isDryRun() {
    [[ ${CLI_DRY_RUN:-0} -eq 1 ]]
}
