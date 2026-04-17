#!/usr/bin/env bash
# purpose:  Run an isolated dialog-backed smoke test without relying on the util-linux `script` command.
# when:     Use for local end-to-end verification of the dialog TUI path on systems where `dialog` exists but `script` does not.
# inputs:   Optional env vars TMPDIR, DIALOG_TRACE, SMOKE_KEEP_WORKSPACE, and TERM; no positional arguments.
# outputs:  Human-readable progress log to stdout and a final SMOKE_RESULT=PASS line on success.
# risk:     safe
# source:   original
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./helpers/smoke_tui_common.sh
source "$SCRIPT_DIR/helpers/smoke_tui_common.sh"

run_tui_backend_smoke dialog "mock-dialog" "Dialog smoke repo" "dialog smoke shader"