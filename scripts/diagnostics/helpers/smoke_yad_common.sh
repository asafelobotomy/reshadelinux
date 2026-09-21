#!/usr/bin/env bash
# Driver for the yad smoke test: a private X server (nothing appears on the user's desktop),
# real yad, and xdotool keystrokes. Sourced by smoke_yad.sh.

# shellcheck source=./smoke_common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/smoke_common.sh"

YADSMOKE_DISPLAY=""
YADSMOKE_XVFB_PID=""
YADSMOKE_WM_PID=""
YADSMOKE_SHOTS="${SMOKE_YAD_SHOTS:-}"
YADSMOKE_DIALOG_WAIT="${SMOKE_YAD_DIALOG_WAIT:-30}"
YADSMOKE_APP_PID=""
YADSMOKE_SHOT_COUNT=0

# Start Xvfb on a free display, and a window manager when one is installed, so windows are
# decorated and focused the way a user sees them. GTK would otherwise pick a Wayland session.
yadsmoke_display_start() {
    local _n

    for _n in $(seq 90 130); do
        [[ -e /tmp/.X${_n}-lock || -e /tmp/.X11-unix/X${_n} ]] && continue
        Xvfb ":$_n" -screen 0 1280x800x24 -nolisten tcp >/dev/null 2>&1 &
        YADSMOKE_XVFB_PID=$!
        YADSMOKE_DISPLAY=":$_n"
        sleep 1.5
        kill -0 "$YADSMOKE_XVFB_PID" 2>/dev/null && break
        YADSMOKE_DISPLAY=""
    done
    [[ -n $YADSMOKE_DISPLAY ]] || { printf 'Could not start Xvfb\n' >&2; return 1; }

    export DISPLAY="$YADSMOKE_DISPLAY" GDK_BACKEND=x11
    unset WAYLAND_DISPLAY
    if command -v openbox >/dev/null 2>&1; then
        openbox >/dev/null 2>&1 &
        YADSMOKE_WM_PID=$!
        sleep 1
    fi
}

# Stopping the X server ends every dialog left on it, so nothing is killed by name: that would
# also hit yad windows the user has open on their own desktop.
yadsmoke_display_stop() {
    if [[ -n $YADSMOKE_WM_PID ]]; then
        kill "$YADSMOKE_WM_PID" 2>/dev/null || true
    fi
    if [[ -n $YADSMOKE_XVFB_PID ]]; then
        kill "$YADSMOKE_XVFB_PID" 2>/dev/null || true
    fi
}

# True when the process runs yad as a progress window. Those are titled like the dialogs around
# them and appear briefly between two of them, so they are never the dialog to answer.
yadsmoke_pid_is_progress() {
    [[ -r /proc/$1/cmdline ]] && tr '\0' ' ' < "/proc/$1/cmdline" | grep -q -- '--progress'
}

# Print "<window id>|<title>" of the newest yad dialog (progress windows are skipped), waiting up
# to YADSMOKE_DIALOG_WAIT seconds.
yadsmoke_next_dialog() {
    local _i _id _pid

    for _i in $(seq 1 $((YADSMOKE_DIALOG_WAIT * 4))); do
        while IFS= read -r _id; do
            _pid=$(xdotool getwindowpid "$_id" 2>/dev/null || true)
            if [[ -n $_pid ]] && yadsmoke_pid_is_progress "$_pid"; then
                continue
            fi
            printf '%s|%s\n' "$_id" "$(xdotool getwindowname "$_id")"
            return 0
        done < <(xdotool search --onlyvisible --class yad 2>/dev/null | tac)
        sleep 0.25
    done
    return 1
}

# yadsmoke_answer "EXPECTED TITLE" KEY... : wait for a dialog with that title, check it, send the
# keys (xdotool key names; "type:text" types text; "sleep" pauses) and wait for it to close.
yadsmoke_answer() {
    local _expected="$1" _dialog _id _title _pid _key _i
    shift

    _dialog=$(yadsmoke_next_dialog) || { printf 'FAIL: no dialog appeared (expected "%s")\n' "$_expected" >&2; return 1; }
    _id="${_dialog%%|*}"
    _title="${_dialog#*|}"
    _pid=$(xdotool getwindowpid "$_id" 2>/dev/null || true)
    if [[ $_title != "$_expected" ]]; then
        printf 'FAIL: expected a dialog titled "%s" but got "%s"\n' "$_expected" "$_title" >&2
        return 1
    fi
    sleep 0.8
    yadsmoke_screenshot "$_expected"
    # A window manager only hands keyboard focus to a window that has been activated.
    xdotool windowactivate "$_id" 2>/dev/null || true
    xdotool windowfocus "$_id" 2>/dev/null || true
    sleep 0.4
    for _key in "$@"; do
        case $_key in
            sleep) sleep 0.5 ;;
            type:*) xdotool type --delay 30 "${_key#type:}" ;;
            *) xdotool key "$_key" ;;
        esac
        sleep 0.3
    done
    # X11 reuses window ids, so the next dialog can get this one's id: every dialog is its own
    # yad process, and the dialog is closed once no window of that process remains.
    for _i in $(seq 1 40); do
        [[ -n $_pid ]] && ! kill -0 "$_pid" 2>/dev/null && return 0
        xdotool getwindowname "$_id" >/dev/null 2>&1 || return 0
        [[ -n $_pid && $(xdotool getwindowpid "$_id" 2>/dev/null) != "$_pid" ]] && return 0
        sleep 0.25
    done
    printf 'FAIL: the "%s" dialog did not close after the keys were sent\n' "$_expected" >&2
    return 1
}

yadsmoke_screenshot() {
    [[ -n $YADSMOKE_SHOTS ]] || return 0
    command -v import >/dev/null 2>&1 || return 0
    mkdir -p "$YADSMOKE_SHOTS"
    YADSMOKE_SHOT_COUNT=$((YADSMOKE_SHOT_COUNT + 1))
    import -window root "$YADSMOKE_SHOTS/${YADSMOKE_SCENARIO:-scenario}-$(printf '%02d' "$YADSMOKE_SHOT_COUNT")-${1//[^A-Za-z0-9]/_}.png" || true
}

# A fake Steam library: three games (one with markup characters in its name) and two local
# shader packs, so no clone is needed.
yadsmoke_workspace() {
    local _ws="$1" _steamapps _repo

    rm -rf "$_ws"
    create_smoke_runtime_workspace "$_ws"
    # The flows only check that 7z exists and never extract anything. A stub at the end of PATH
    # keeps a machine without it usable, and a real 7z still takes precedence.
    mkdir -p "$_ws/fake-bin"
    printf '#!/bin/sh\nexit 0\n' > "$_ws/fake-bin/7z"
    chmod +x "$_ws/fake-bin/7z"
    _steamapps="$_ws/home/.local/share/Steam/steamapps"
    mkdir -p "$_steamapps/common/AutoGame/bin" "$_steamapps/common/Tom Jerry/x64" "$_steamapps/common/Third"
    touch "$_steamapps/common/AutoGame/bin/AutoGame.exe" "$_steamapps/common/Tom Jerry/x64/TomJerry.exe" \
        "$_steamapps/common/Third/Third.exe"
    write_smoke_manifest "$_steamapps" 1001 "Auto Game" "AutoGame"
    write_smoke_manifest "$_steamapps" 1002 "Tom & Jerry <Demo>" "Tom Jerry"
    write_smoke_manifest "$_steamapps" 1003 "Third Game" "Third"
    for _repo in repo-a repo-b; do
        mkdir -p "$_ws/reshade/ReShade_shaders/$_repo/Shaders" "$_ws/reshade/ReShade_shaders/$_repo/Textures"
        printf '// %s\n' "$_repo" > "$_ws/reshade/ReShade_shaders/$_repo/Shaders/$_repo.fx"
        printf 'texture\n' > "$_ws/reshade/ReShade_shaders/$_repo/Textures/$_repo.png"
    done
}

# yadsmoke_start_app WORKSPACE LOG [VAR=value...] [-- ARGUMENT...]: run the installer on the yad
# backend in the background, with extra environment settings and command-line arguments.
yadsmoke_start_app() {
    local _ws="$1" _log="$2" _env=() _args=()
    shift 2

    while (( $# > 0 )) && [[ $1 != -- ]]; do
        _env+=("$1")
        shift
    done
    (( $# > 0 )) && shift
    _args=("$@")

    setsid --wait env HOME="$_ws/home" MAIN_PATH="$_ws/reshade" UI_BACKEND=yad UPDATE_RESHADE=0 \
        PATH="$PATH:$_ws/fake-bin" \
        SHADER_REPOS='local|repo-a||Repo A|Alpha & <beta> pack;local|repo-b||Repo B|Second pack' \
        "${_env[@]}" "$SMOKE_COMMON_ENTRYPOINT" "${_args[@]}" > "$_log" 2>&1 &
    YADSMOKE_APP_PID=$!
}

# Wait for the installer to finish; print its exit status.
yadsmoke_app_status() {
    local _status=0

    wait "$YADSMOKE_APP_PID" || _status=$?
    printf '%s\n' "$_status"
}

# EXIT trap: stop the display, then run the shared smoke_finish with the status the run ended
# with (stopping the display would otherwise replace it, and a failing run would be cleaned up
# as if it had passed).
yadsmoke_finish() {
    local _status=$?

    yadsmoke_display_stop
    (exit "$_status")
    smoke_finish "$1"
}

# Stop the installer and every dialog it started (they share its process group).
yadsmoke_abort_app() {
    if [[ -n $YADSMOKE_APP_PID ]]; then
        kill -TERM -- "-$YADSMOKE_APP_PID" 2>/dev/null || true
        wait "$YADSMOKE_APP_PID" 2>/dev/null || true
    fi
    return 0
}
