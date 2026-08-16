#!/bin/bash
# Wakes both displays (DP-6 via DPMS, TV via WebOS) on the first real input
# activity while hyprlock is up, instead of waiting for a full unlock.
#
# Why: Hyprland suppresses monitor wake-on-input entirely while the session
# is held by ext-session-lock (hyprlock) — confirmed this affects every
# output, not just the TV: DP-6 doesn't auto-wake on activity while locked
# either, only Hyprland's own resume-on-unlock does. libinput reads raw
# evdev directly, bypassing that suppression, so we drive both wakes here.

pgrep -x hyprlock >/dev/null || exit 0

FIFO=$(mktemp -u /tmp/display-activity-XXXXXX.fifo)
mkfifo "$FIFO"
trap 'kill "$LIBINPUT_PID" 2>/dev/null; rm -f "$FIFO"' EXIT

stdbuf -oL libinput debug-events >"$FIFO" 2>/dev/null &
LIBINPUT_PID=$!

while IFS= read -r line; do
    case "$line" in
    *POINTER_MOTION*|*POINTER_BUTTON*|*KEYBOARD_KEY*|*POINTER_SCROLL*|*TOUCH_DOWN*|*GESTURE*)
        break
        ;;
    esac
    pgrep -x hyprlock >/dev/null || break
done <"$FIFO"

kill "$LIBINPUT_PID" 2>/dev/null

if pgrep -x hyprlock >/dev/null; then
    hyprctl dispatch dpms on DP-6
    omarchy-brightness-keyboard restore
    ~/.local/lgpowercontrol/tv-on.sh
fi
