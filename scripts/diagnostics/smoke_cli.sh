#!/usr/bin/env bash
# purpose:  Run an isolated CLI smoke test that covers interactive install and seeded --update-all relink flows.
# when:     Use for local end-to-end verification of the CLI without touching real games or user ReShade data.
# inputs:   Optional env vars TMPDIR and UI_BACKEND; no positional arguments.
# outputs:  Human-readable progress log to stdout and a final SMOKE_RESULT=PASS line on success.
# risk:     safe
# source:   original
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./helpers/smoke_cli_common.sh
source "$SCRIPT_DIR/helpers/smoke_cli_common.sh"

run_cli_smoke_suite 0