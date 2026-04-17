#!/usr/bin/env bash
# purpose:  Preserve the historical dialog test entrypoint while delegating to the maintained dialog smoke runner.
# when:     Use only when older notes or shell history still reference test_dialog.sh.
# inputs:   Optional env vars TMPDIR, DIALOG_TRACE, SMOKE_KEEP_WORKSPACE, and TERM; no positional arguments.
# outputs:  The delegated dialog smoke output.
# risk:     safe
# source:   original
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/smoke_dialog.sh" "$@"