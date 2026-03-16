# shellcheck shell=bash
# shellcheck disable=SC1091

_STEAM_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"

. "$_STEAM_LIB_DIR/steam_detection.sh" || { printf 'Failed to source %s\n' "$_STEAM_LIB_DIR/steam_detection.sh" >&2; return 1; }
. "$_STEAM_LIB_DIR/steam_metadata.sh" || { printf 'Failed to source %s\n' "$_STEAM_LIB_DIR/steam_metadata.sh" >&2; return 1; }