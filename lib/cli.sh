# shellcheck shell=bash

function printUsage() {
    printf 'Usage: %s [options]\n' "$0"
    printf '  --update-all              Re-link ReShade for all previously installed games.\n'
    printf '  --cli                     Force the plain CLI backend.\n'
    printf '  --ui-backend=<backend>    Force auto, yad, whiptail, dialog, or cli.\n'
    printf '  --game-path=<path>        Use an explicit game directory or .exe path.\n'
    printf '  --app-id=<appid>          Select a detected Steam game by App ID, or persist it with --game-path.\n'
    printf '  --dll-override=<name>     Use an explicit ReShade DLL override, e.g. dxgi or d3d9.\n'
    printf '  --shader-repos=<value>    Use all, none, or a comma-separated repo list. With --update-all, override the tracked repos for every game in the batch.\n'
    printf '  --list-shader-repos       Print the configured shader repo names and labels.\n'
    printf '  --version, -V             Show the script version.\n'
    printf '  --help, -h                Show this help message.\n'
}

function printCliVersion() {
    printf '%s\n' "${SCRIPT_VERSION:-unknown}"
}

function printAvailableShaderRepos() {
    local _savedIFS="$IFS" _entry _label
    IFS=';' read -ra _allRepos <<< "$SHADER_REPOS"
    IFS="$_savedIFS"

    printf 'Configured shader repositories:\n'
    for _entry in "${_allRepos[@]}"; do
        parseShaderRepoEntry "$_entry"
        [[ -z $_shaderRepoName ]] && continue
        _label=$(formatShaderRepoDisplayLabel "$_shaderRepoUri" "$_shaderRepoName" "$_shaderRepoDesc")
        printf '  %s\t%s\n' "$_shaderRepoName" "$_label"
    done
}

function handleCliInfoArgs() {
    if [[ ${CLI_LIST_SHADER_REPOS:-0} -eq 1 ]]; then
        printAvailableShaderRepos
        exit 0
    fi
}

function parseCliArgs() {
    _BATCH_UPDATE=0
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

    local _arg
    for _arg in "$@"; do
        case "$_arg" in
            --update-all)
                _BATCH_UPDATE=1
                ;;
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
            --list-shader-repos)
                CLI_LIST_SHADER_REPOS=1
                ;;
            --version|-V)
                printCliVersion
                exit 0
                ;;
            --help|-h)
                printUsage
                exit 0
                ;;
            *)
                printf 'Unknown argument: %s\n\n' "$_arg" >&2
                printUsage >&2
                exit 1
                ;;
        esac
    done
}

function _trim_cli_value() {
    local _value="$1"
    _value="${_value#"${_value%%[![:space:]]*}"}"
    _value="${_value%"${_value##*[![:space:]]}"}"
    printf '%s\n' "$_value"
}

function validateCliArgs() {
    if [[ ${CLI_FORCE_CLI_SET:-0} -eq 1 && ${CLI_UI_BACKEND_SET:-0} -eq 1 ]]; then
        printErr "Use either --cli or --ui-backend=<backend>, not both."
    fi

    if [[ $_BATCH_UPDATE -eq 1 ]]; then
        if [[ ${CLI_GAME_PATH_SET:-0} -eq 1 || ${CLI_APP_ID_SET:-0} -eq 1 || ${CLI_DLL_OVERRIDE_SET:-0} -eq 1 ]]; then
            printErr "--update-all cannot be combined with --game-path, --app-id, or --dll-override. Use --shader-repos if you need to override shader selection for every tracked game."
        fi
    fi

    if [[ ${CLI_GAME_PATH_SET:-0} -eq 1 ]]; then
        CLI_GAME_PATH="$(_trim_cli_value "$CLI_GAME_PATH")"
    fi

    if [[ ${CLI_APP_ID_SET:-0} -eq 1 ]]; then
        CLI_APP_ID="$(_trim_cli_value "$CLI_APP_ID")"
        [[ $CLI_APP_ID =~ ^[0-9]+$ ]] || printErr "The App ID supplied via --app-id must be numeric."
    fi

    if [[ ${CLI_DLL_OVERRIDE_SET:-0} -eq 1 ]]; then
        CLI_DLL_OVERRIDE="$(_trim_cli_value "$CLI_DLL_OVERRIDE")"
        CLI_DLL_OVERRIDE="${CLI_DLL_OVERRIDE,,}"
        CLI_DLL_OVERRIDE="${CLI_DLL_OVERRIDE%.dll}"
        isKnownDllOverride "$CLI_DLL_OVERRIDE" || printErr "Unknown DLL override '$CLI_DLL_OVERRIDE'. Expected one of: $COMMON_OVERRIDES"
    fi

    if [[ ${CLI_SHADER_REPOS_SET:-0} -eq 1 ]]; then
        CLI_SHADER_REPOS=$(normalizeRequestedShaderRepos "$CLI_SHADER_REPOS") || printErr "Invalid value supplied via --shader-repos. Use all, none, or a comma-separated list of configured repo names."
    fi
}