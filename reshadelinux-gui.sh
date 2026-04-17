#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v yad >/dev/null 2>&1; then
	export UI_BACKEND=yad
else
	printf 'Warning: yad is not installed; falling back to the default UI backend.\n' >&2
	export UI_BACKEND=auto
fi

exec "$HERE/reshadelinux.sh" "$@"