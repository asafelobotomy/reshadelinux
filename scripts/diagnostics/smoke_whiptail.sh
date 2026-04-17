#!/usr/bin/env bash
# purpose:  Run an isolated whiptail-backed smoke test with automatic UI progression.
# when:     Use for local end-to-end verification of the whiptail TUI path without touching real games or user ReShade data.
# inputs:   Optional env vars TMPDIR, SMOKE_KEEP_WORKSPACE, and TERM; no positional arguments.
# outputs:  Human-readable progress log to stdout and a final SMOKE_RESULT=PASS line on success.
# risk:     safe
# source:   original
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./helpers/smoke_tui_common.sh
source "$SCRIPT_DIR/helpers/smoke_tui_common.sh"

run_tui_backend_smoke whiptail "mock-whiptail" "Whiptail smoke repo" "whiptail smoke shader"