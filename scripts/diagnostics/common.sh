#!/bin/bash

# Mirror the production script's shell behavior so sourced helpers behave the same here.
set -eu

DIAGNOSTICS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$DIAGNOSTICS_DIR/../.." && pwd)"

source "$REPO_DIR/lib/logging.sh"
source "$REPO_DIR/lib/ui.sh"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/config.sh"
source "$REPO_DIR/lib/state.sh"
source "$REPO_DIR/lib/shaders.sh"
source "$REPO_DIR/lib/steam.sh"

export UI_BACKEND="${UI_BACKEND:-cli}"
export MAIN_PATH="${MAIN_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/reshade}"
init_runtime_config