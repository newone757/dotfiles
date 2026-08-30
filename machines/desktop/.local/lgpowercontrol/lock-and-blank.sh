#!/bin/bash
# Lock the session and blank the LG TV panel.
# Quattro replacement for the inline bash that used to live in bindings.conf.
# Staged 2026-08-30 — NOT yet installed. Test after upgrading, then copy to
# ~/.local/lgpowercontrol/lock-and-blank.sh
#
# TWO THINGS CHANGED FROM THE 3.8.4 VERSION:
#
# 1. `pgrep -x hyprlock` is dead — hyprlock is uninstalled by Quattro. Lock
#    state now comes from `omarchy-hyprland-session-locked`:
#       exit 0 = locked, 1 = unlocked, 2 = undetermined
#    Its own docs say callers branching on success should treat 2 as unlocked,
#    which is what the loop below does.
#
# 2. `OMARCHY_LOCK_ONLY=true` is GONE — the variable is not referenced anywhere
#    in 4.0.1. It existed to suppress omarchy-system-lock's background
#    "dpms off" across ALL monitors (which cut the TV's HDMI signal and made it
#    show a "No Signal" banner). Quattro's omarchy-system-lock no longer does
#    any dpms itself; it just calls `omarchy-shell lock lock`.
#
#    ⚠️  UNVERIFIED: its summary line still reads "Lock the computer and turn
#    off the display", so the Quickshell lock may blank displays internally.
#    If the TV shows "No Signal" on lock after upgrading, that's this — and the
#    fix will be in shell.json / the lock plugin, not here.

set -uo pipefail

BSCPYLGTV="$HOME/.local/lgpowercontrol/bscpylgtv/bin/bscpylgtvcommand"
TV_IP=10.0.1.28
SECONDARY=DP-6

is_locked() {
  omarchy-hyprland-session-locked
  # 0 = locked; 1 and 2 both treated as unlocked
  [[ $? -eq 0 ]]
}

omarchy-system-lock

# Give the lock surface time to spawn and configure itself on HDMI-A-2 before
# blanking. Sending turn_screen_off mid-setup triggers an HDMI renegotiation
# that flips the TV back to "signal active" and undoes the blank. This was
# tuned to 3s under hyprlock; re-tune against the Quickshell lock if the TV
# stops blanking reliably.
blank_after_settle() {
  sleep 3
  hyprctl dispatch dpms off "$SECONDARY"
  timeout 10 "$BSCPYLGTV" "$TV_IP" turn_screen_off >/dev/null 2>&1
  # Watch for real input activity and wake both displays early.
  timeout 7200 "$HOME/.local/lgpowercontrol/wake-displays-on-activity.sh" &
}

blank_after_settle &
BLANK_PID=$!

# Wait for unlock, then restore.
while is_locked; do sleep 1; done

kill "$BLANK_PID" 2>/dev/null
"$HOME/.local/lgpowercontrol/tv-on.sh"
