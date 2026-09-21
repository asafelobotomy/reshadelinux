#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run this script again inside the first terminal emulator that is installed and keep the window
# open at the end so the result can be read. Each emulator has its own way to run a command, and
# the flag that makes it wait matters: an AppImage is unmounted as soon as its launcher exits.
#
# TERMINAL_STATUS is the installer's exit status. Emulators disagree on what they return (xterm
# exits 0 whatever its command did), so the run inside the terminal writes its status to a file
# that is read back here. If that file stays empty the installer never ran: an emulator that could
# not be started (126 or 127) is skipped, and any other status is returned as it is. Either way a
# cancelled or failed install is never started a second time in another emulator. Returns 1 when
# no emulator is installed.
TERMINAL_STATUS=0
open_in_terminal() {
    local _term _flags _statusFile _installerStatus
    # shellcheck disable=SC2016  # the inner bash expands this, not this shell
    local _runner='"$0" "$@"; _status=$?; [ -z "$RESHADELINUX_STATUS_FILE" ] || printf "%s" "$_status" > "$RESHADELINUX_STATUS_FILE"; printf "\nPress Enter to close..."; read -r _; exit "$_status"'

    for _term in x-terminal-emulator gnome-terminal konsole xfce4-terminal mate-terminal lxterminal \
        terminator tilix alacritty kitty foot wezterm xterm; do
        command -v "$_term" >/dev/null 2>&1 || continue
        case $_term in
            gnome-terminal) _flags=(--wait --) ;;
            konsole) _flags=(--nofork -e) ;;
            xfce4-terminal) _flags=(--disable-server -x) ;;
            mate-terminal|terminator) _flags=(-x) ;;
            kitty|foot) _flags=() ;;
            wezterm) _flags=(start --always-new-process --) ;;
            *) _flags=(-e) ;;
        esac
        _statusFile=$(mktemp) || _statusFile=""
        TERMINAL_STATUS=0
        RESHADELINUX_IN_TERMINAL=1 RESHADELINUX_STATUS_FILE="$_statusFile" \
            "$_term" "${_flags[@]}" bash -c "$_runner" "$0" "$@" || TERMINAL_STATUS=$?
        _installerStatus=""
        if [[ -n $_statusFile ]]; then
            _installerStatus=$(<"$_statusFile")
            rm -f "$_statusFile"
        fi
        if [[ $_installerStatus =~ ^[0-9]+$ ]]; then
            TERMINAL_STATUS=$_installerStatus
            return 0
        fi
        [[ $TERMINAL_STATUS -eq 126 || $TERMINAL_STATUS -eq 127 ]] && continue
        return 0
    done
    return 1
}

if command -v yad >/dev/null 2>&1; then
    export UI_BACKEND=yad
else
    printf 'Warning: yad is not installed; falling back to the default UI backend.\n' >&2
    # The text interface needs a terminal, and a desktop launch (Terminal=false) has none, so
    # without this the application would simply never appear. A desktop launch passes no
    # arguments: a run with arguments is a script or a shortcut (the release tool's --update-all
    # check, cron), and a window that waits for Enter would hang it.
    if [[ $# -eq 0 && ! -t 0 && ! -t 1 && -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} && -z ${RESHADELINUX_IN_TERMINAL:-} ]]; then
        if open_in_terminal "$@"; then
            exit "$TERMINAL_STATUS"
        fi
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "ReShadeLinux" "Install yad for the graphical interface, or run reshadelinux-gui.sh from a terminal." || true
        fi
    fi
    export UI_BACKEND=auto
fi

exec "$HERE/reshadelinux.sh" "$@"
