#!/bin/bash
# Wakes both displays (DP-6 via DPMS, TV via WebOS) on the first real input
# activity while the session is locked, instead of waiting for a full unlock.
#
# Quattro port of ~/.local/lgpowercontrol/wake-displays-on-activity.sh.
# Staged 2026-08-30 — NOT yet installed.
#
# ONLY CHANGE vs the 3.8.4 version: every `pgrep -x hyprlock` became
# `omarchy-hyprland-session-locked`, because Quattro uninstalls hyprlock. Left
# unported, this script would silently exit at the first line and the displays
# would stay dark until a full unlock — a quiet failure, not a loud one, which
# is exactly the kind worth catching before it bites.
#
# Why this exists at all: Hyprland suppresses monitor wake-on-input while the
# session is held by ext-session-lock — confirmed to affect every output, not
# just the TV. libinput reads raw evdev directly, bypassing that suppression,
# so we drive both wakes here.
#
# ⚠️  VERIFY AFTER UPGRADING: this assumes Quattro's Quickshell lock still holds
# an ext-session-lock and still suppresses wake-on-input the same way. If the
# new lock wakes displays on its own, this script becomes redundant — check
# before keeping it.

is_locked() {
  omarchy-hyprland-session-locked
  [[ $? -eq 0 ]]
}

is_locked || exit 0

FIFO=$(mktemp -u /tmp/display-activity-XXXXXX.fifo)
mkfifo "$FIFO"
trap 'kill "$LIBINPUT_PID" 2>/dev/null; rm -f "$FIFO"' EXIT

stdbuf -oL libinput debug-events >"$FIFO" 2>/dev/null &
LIBINPUT_PID=$!

# Only a MATCHED input event may wake the displays. The read loop also ends on
# EOF -- if `libinput debug-events` dies for any reason the FIFO closes -- and
# the wake block used to run then too, switching the panels and the TV back on
# with nobody touching anything. Tracked explicitly rather than inferred from
# the loop having ended.
saw_input=0

while IFS= read -r line; do
    case "$line" in
    *POINTER_MOTION*|*POINTER_BUTTON*|*KEYBOARD_KEY*|*POINTER_SCROLL*|*TOUCH_DOWN*|*GESTURE*)
        saw_input=1
        break
        ;;
    esac
    is_locked || break
done <"$FIFO"

kill "$LIBINPUT_PID" 2>/dev/null

if (( ! saw_input )); then
    # Timed out, unlocked, or the event source went away. Nothing to wake for.
    exit 0
fi

if is_locked; then
    hyprctl dispatch 'hl.dsp.dpms({ action = "enable", monitor = "DP-6" })'
    omarchy-brightness-keyboard restore
    "$HOME/.local/lgpowercontrol/tv-on.sh"
fi
