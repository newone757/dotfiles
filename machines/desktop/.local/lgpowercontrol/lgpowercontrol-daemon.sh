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

# After input wakes the displays while the session is STILL locked, how long to
# wait for an actual unlock before blanking again. Long enough to type a
# password, short enough that a stray event does not leave the TV lit for hours.
REBLANK_GRACE_SECS=90

# Serializes blank vs restore. Both take this before touching TV power, so a
# blank that is still settling cannot land after a restore has already run.
TV_STATE_LOCK=/tmp/lgpowercontrol-tv-state.lock
# ---------------------------------------------------------------------------

log() { echo "$*" | logger --tag lgpowercontrol-daemon; }

# omarchy-hyprland-session-locked: 0 = locked, 1 = unlocked, 2 = undetermined.
# Its own docs say callers branching on success should treat 2 as unlocked.
is_locked() {
  omarchy-hyprland-session-locked
  [[ $? -eq 0 ]]
}

# Blank the panel, then keep watching. If input wakes the displays while the
# session is still locked and no unlock follows, blank again.
#
# Why the loop exists: under 3.8.4 hypridle owned a repeating idle timer, so a
# wake that was not followed by an unlock simply timed out and re-blanked. This
# daemon reacts to lock STATE TRANSITIONS instead, which covers every lock path
# but fires only once -- so before this loop, a single stray input event
# (walking past, a nudged mouse) woke the TV and left it showing the lock screen
# indefinitely. Observed 2026-09-05: blanked 01:32:58, woken by input 01:47:45,
# still sitting on the lock screen at 02:07 when the session was unlocked.
tv_blank_loop() {
  local first=1 waited

  while is_locked; do
    if (( first )); then
      log "locked -- blanking panel (TV stays powered)"
      # Sending turn_screen_off while the lock surface is still configuring on
      # HDMI-A-2 triggers a renegotiation that undoes the blank. Only needed on
      # the first pass; later passes happen long after the lock is established.
      sleep "$BLANK_SETTLE_SECS"
      first=0
    fi

    exec 8>"$TV_STATE_LOCK"
    flock 8
    # Re-check under the lock: a quick lock->unlock inside the settle would
    # otherwise blank the panel after tv_restore already ran.
    if ! is_locked; then
      log "blank aborted -- session unlocked during the ${BLANK_SETTLE_SECS}s settle"
      flock -u 8
      return
    fi

    # Scope the DPMS to the secondary only. HDMI-A-2 is deliberately left alone:
    # the TV is still fully powered here, so cutting its HDMI signal makes it
    # show a "No Signal" banner instead of going quiet.
    hyprctl dispatch "hl.dsp.dpms({ action = \"disable\", monitor = \"$SECONDARY\" })" >/dev/null 2>&1
    timeout 15 "$BSCPYLGTV" "$TV_IP" turn_screen_off >/dev/null 2>&1 ||
      log "WARN: turn_screen_off failed"
    flock -u 8

    # Blocks until real input arrives or the session unlocks. Hyprland
    # suppresses wake-on-input for every output while an ext-session-lock is
    # held; libinput reads raw evdev and bypasses that.
    timeout 7200 "$HOME/.local/lgpowercontrol/wake-displays-on-activity.sh"

    is_locked || break

    log "woken while still locked -- re-blanking in ${REBLANK_GRACE_SECS}s unless unlocked"
    waited=0
    while (( waited < REBLANK_GRACE_SECS )); do
      sleep 5
      waited=$(( waited + 5 ))
      is_locked || break 2
    done
  done
}

tv_deep_off() {
  log "deep idle -- powering TV off"
  exec 8>"$TV_STATE_LOCK"
  flock 8

  # Why this is noisy on purpose: from 2026-08-30 to 09-04 this fired four
  # times and logged "power_off failed" every time, with no detail, while the
  # TV stayed powered (it started nagging about screen maintenance). The old
  # call discarded both stdout and stderr, so there was nothing to diagnose.
  #
  # Two candidate causes, indistinguishable without the real error:
  #   1. power_off deliberately does NOT wait for a response ("response is
  #      unreliable"), so runloop's following client.disconnect() can throw
  #      against a TV that is already shutting down -- a non-zero exit after a
  #      SUCCESSFUL power off.
  #   2. The call never completes: connect retries (9 attempts) plus the
  #      2s connect timeout can exceed the old `timeout 10`, killing it before
  #      POWER_OFF is ever sent.
  # Only (2) matches the TV staying on, but capture the evidence rather than
  # guess. Timeout raised to 30s so a slow connect is no longer a false
  # failure, and the state is re-read afterwards to record what actually
  # happened.
  local out rc state
  out=$(timeout 30 "$BSCPYLGTV" "$TV_IP" power_off 2>&1)
  rc=$?
  if (( rc != 0 )); then
    log "WARN: power_off exited $rc -- output: ${out:-<none>}"
  else
    log "power_off returned 0 -- output: ${out:-<none>}"
  fi

  sleep 5
  # An UNREACHABLE TV here means success: WebOS refuses the websocket while it
  # shuts down, so the client raises ConnectionClosedError 1008 "Try Again Later
  # (EWS)". Confirmed 2026-09-04 -- power_off returned 0 and this check then
  # dumped a 20-line Python traceback into the journal for a power-off that had
  # worked perfectly. Log the outcome, not the stack.
  if state=$(timeout 15 "$BSCPYLGTV" "$TV_IP" get_power_state 2>/dev/null); then
    case "$state" in
      *"'state': 'Active'"*)
        log "WARN: TV still reports Active after power_off -- it did not power down" ;;
      *)
        log "post power_off state: $state" ;;
    esac
  else
    log "TV unreachable after power_off, as expected when it powers down"
  fi

  flock -u 8
}

tv_restore() {
  log "unlocked -- restoring displays"
  # Blocks until any in-flight blank finishes, so restore is always last.
  exec 8>"$TV_STATE_LOCK"
  flock 8
  hyprctl dispatch "hl.dsp.dpms({ action = \"enable\", monitor = \"$SECONDARY\" })" >/dev/null 2>&1
  # tv-on.sh flocks and checks get_power_state itself, so it is safe to call
  # redundantly and picks the fast path (turn_screen_on) vs the slow one
  # (WoL + HDMI handshake) automatically.
  "$HOME/.local/lgpowercontrol/tv-on.sh"
  flock -u 8
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
      tv_blank_loop &
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
