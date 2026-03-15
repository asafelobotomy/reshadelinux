#!/bin/bash
# Test loader for the production reshade-linux libraries.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$REPO_DIR/lib/logging.sh"

# Tests need error reporting without aborting the entire shell.
function printErr() {
    printf '%b[ERROR] %s%b\n' "${_RED:-}" "$*" "${_R:-}" >&2
    return 1
}

source "$REPO_DIR/lib/ui.sh"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/config.sh"
source "$REPO_DIR/lib/state.sh"
source "$REPO_DIR/lib/shaders.sh"
source "$REPO_DIR/lib/steam.sh"

_UI_BACKEND=cli
export GLOBAL_INI=ReShade.ini