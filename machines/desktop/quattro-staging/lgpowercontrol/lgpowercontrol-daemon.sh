#!/bin/bash
# LG TV power control daemon — Omarchy 4 "Quattro" replacement for the three
# hypridle listeners that Quattro deletes.
#
# Staged 2026-08-30. NOT yet installed, NOT yet tested against Quattro.
# Install to ~/.local/lgpowercontrol/lgpowercontrol-daemon.sh after upgrading.
#
# ---------------------------------------------------------------------------
# WHY THIS EXISTS
#
# Under 3.8.4, TV power was driven by hypridle listeners with arbitrary
# on-timeout/on-resume shell commands. Quattro removes hypridle entirely; idle
# lives inside the Quickshell process, configured by two integers in
# ~/.config/omarchy/shell.json, with NO command hook of any kind.
#
# So instead of racing the shell with a second idle timer, this watches the one
# thing the shell reliably exposes — LOCK STATE — and drives everything off
# that. Consequences:
#
#   * Every lock path behaves identically: idle timeout, SUPER+CTRL+L, the
#     system menu, `omarchy system lock`. Under 3.8.4 only the paths that had
#     TV commands bolted onto them worked.
#   * Stay-awake (SUPER+CTRL+I) is honored for free — if the session never
#     locks, this never fires. No special-casing needed.
#   * Only one timer left to maintain: the deep power-off escalation.
#
# ---------------------------------------------------------------------------
# STAGE MAPPING vs the old hypridle config
#
#   hypridle 152s  lock + turn_screen_off   ->  on lock transition (below)
#   hypridle 3600s lock + power_off         ->  DEEP_AFTER_LOCK_SECS (below)
#   hypridle on-resume                      ->  on unlock transition (below)
#
# The old screensaver listener (150s) needs nothing here — Quattro's shell owns
# the screensaver via shell.json.
#
# ---------------------------------------------------------------------------
# WHY POLLING RATHER THAN D-BUS
#
# lgpowercontrol-dbus-events.sh listens for org.freedesktop.ScreenSaver
# lock/unlock signals. That MAY keep working under Quattro — it's
# compositor-independent — but it depends on the Quickshell lock emitting those
# signals, which is unverified. Polling `omarchy-hyprland-session-locked` makes
# no assumption about what the shell emits. It costs one hyprctl+jq every 2s,
# which is negligible.
#
# If you confirm the D-Bus signals do fire, you can switch to event-driven and
# drop the poll. Run the two in parallel only briefly — both would fight over
# tv-on.sh (which flocks, so it degrades safely rather than breaking).

set -uo pipefail

# --- configuration ---------------------------------------------------------
TV_IP=10.0.1.28
TV_MAC=00:a1:59:35:35:da
SECONDARY=DP-6
BSCPYLGTV="$HOME/.local/lgpowercontrol/bscpylgtv/bin/bscpylgtvcommand"

POLL_SECS=2

# Seconds after LOCK before escalating from "panel blanked, TV still powered"
# to a real power_off. The old config escalated at 3600s of IDLE; since lock now
# happens at shell.json's `lock` value, this is (3600 - lock_timeout). With the
# default lock of 300s that's 3300. Set to 0 to disable escalation entirely.
DEEP_AFTER_LOCK_SECS=3300

# Delay between the lock appearing and blanking the panel. Sending
# turn_screen_off while the lock surface is still configuring on HDMI-A-2
# triggers an HDMI renegotiation that flips the TV back to "signal active" and
# undoes the blank. Tuned to 3s against hyprlock; RE-TUNE against the
# Quickshell lock if blanking becomes unreliable.
BLANK_SETTLE_SECS=3
# ---------------------------------------------------------------------------

log() { echo "$*" | logger --tag lgpowercontrol-daemon; }

# omarchy-hyprland-session-locked: 0 = locked, 1 = unlocked, 2 = undetermined.
# Its own docs say callers branching on success should treat 2 as unlocked.
is_locked() {
  omarchy-hyprland-session-locked
  [[ $? -eq 0 ]]
}

tv_blank() {
  log "locked -- blanking panel (TV stays powered)"
  sleep "$BLANK_SETTLE_SECS"

  # Scope the DPMS to the secondary only. HDMI-A-2 is deliberately left alone:
  # the TV is still fully powered here, so cutting its HDMI signal makes it show
  # a "No Signal" banner instead of going quiet.
  hyprctl dispatch dpms off "$SECONDARY" >/dev/null 2>&1

  timeout 10 "$BSCPYLGTV" "$TV_IP" turn_screen_off >/dev/null 2>&1 ||
    log "WARN: turn_screen_off failed"

  # Wake both displays on the first real input, without waiting for a full
  # unlock. Hyprland suppresses wake-on-input for every output while an
  # ext-session-lock is held; libinput reads raw evdev and bypasses that.
  timeout 7200 "$HOME/.local/lgpowercontrol/wake-displays-on-activity.sh" &
}

tv_deep_off() {
  log "deep idle -- powering TV off"
  timeout 10 "$BSCPYLGTV" "$TV_IP" power_off >/dev/null 2>&1 ||
    log "WARN: power_off failed"
}

tv_restore() {
  log "unlocked -- restoring displays"
  hyprctl dispatch dpms on "$SECONDARY" >/dev/null 2>&1
  # tv-on.sh flocks and checks get_power_state itself, so it is safe to call
  # redundantly and picks the fast path (turn_screen_on) vs the slow one
  # (WoL + HDMI handshake) automatically.
  "$HOME/.local/lgpowercontrol/tv-on.sh"
}

# --- state machine ---------------------------------------------------------
locked=0
locked_at=0
escalated=0

log "started (poll=${POLL_SECS}s, deep-off after ${DEEP_AFTER_LOCK_SECS}s locked)"

while true; do
  if is_locked; then
    if (( ! locked )); then
      locked=1
      locked_at=$(date +%s)
      escalated=0
      tv_blank &
    elif (( ! escalated && DEEP_AFTER_LOCK_SECS > 0 )); then
      if (( $(date +%s) - locked_at >= DEEP_AFTER_LOCK_SECS )); then
        escalated=1
        tv_deep_off
      fi
    fi
  else
    if (( locked )); then
      locked=0
      escalated=0
      tv_restore
    fi
  fi

  sleep "$POLL_SECS"
done
