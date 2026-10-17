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
#   hypridle 3600s lock + power_off         ->  DEEP_AFTER_DARK_SECS (below)
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
# to a real power_off. Total target is 3600s of idle; blanking happens at
# shell.json's `idle.screensaver` (300s), so this is 3600 - 300 = 3300.
# If you change idle.screensaver, re-derive this. 0 disables escalation.
DEEP_AFTER_DARK_SECS=3300

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

# How often to check, while locked, whether something turned the panel back on.
BLANK_POLL_SECS=5

# How often, while locked and believing the screen is blanked, to ask the TV
# what its screen is ACTUALLY doing. Every failure so far that left the panel
# lit came from event logic being subtly wrong, so this checks the device
# itself rather than trusting our own bookkeeping. One WebOS query per interval.
TV_VERIFY_SECS=300
STREAM_VERIFY_SECS=60

# Present while a Moonlight stream found the displays dark: they stay dark for
# the rest of the stream AND after it ends, until real input at this desk.
HOLD_FILE="$XDG_RUNTIME_DIR/lgpowercontrol-hold"

# Last idle/active reading from activity-monitor/shell.qml (3s threshold).
ACTIVITY_FILE="$XDG_RUNTIME_DIR/lgpowercontrol-activity"
BLANK_TV_FAILED=0

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

# The shell's own IdleMonitor (timeout = idle.screensaver in shell.json, since
# lock is pushed out to ~25 days). Respects inhibitors, so a browser Video Wake
# Lock or a game holding idle-inhibit keeps the TV lit, same as before.
is_idle() {
  [[ $(omarchy-shell idle status 2>/dev/null | jq -r '.idle' 2>/dev/null) == true ]]
}

# Displays should be dark when idle OR manually locked.
#
# 2026-10-17: lock and screensaver were turned off for Moonlight -- a locked
# session needs a password typed on devices with no keyboard. Blanking now
# keys off idle; a manual lock (SUPER+CTRL+L) still blanks immediately.
# A Moonlight session is running (sunshine-stream-begin/-end in ~/.local/bin).
# Requires BOTH the flag file and the headless output: a stale flag left by a
# stream that died without running -end must never keep the TV dark while
# someone is sitting at it.
is_streaming() {
  [[ -e "$XDG_RUNTIME_DIR/sunshine-streaming" ]] &&
    hyprctl monitors -j 2>/dev/null | jq -e 'any(.[]; .name == "sunshine")' >/dev/null 2>&1
}

# Displays should be dark when idle, manually locked, or held dark.
#
# Streaming must not change the physical displays in EITHER direction: dark
# when a stream starts -> dark until someone touches this PC (not "until the
# stream ends"); lit when it starts -> left alone. Stream input is ordinary
# input to the shell, so the dark case needs the hold, otherwise the first
# Moonlight keypress would light the TV in an empty room.
#
# Known limit: displays lit at stream start stay lit for the whole stream,
# since stream input keeps resetting idle and cannot be told apart from local
# input without raw evdev access (user is not in `input`).
is_held() {
  [[ -e "$HOLD_FILE" ]]
}

is_dark() {
  is_locked || is_idle || is_held
}

# Keep the displays blanked for as long as the session is locked.
#
# WHY THIS RECONCILES STATE RATHER THAN WATCHING FOR INPUT
#
# The previous version blanked once, then waited on
# wake-displays-on-activity.sh (a libinput watcher) to tell it the displays had
# woken. That assumed this daemon was the only thing that could turn a display
# back on while locked. It is not: Quattro's own idle service reacts to activity
# by running `omarchy-system-wake`, which calls `omarchy-brightness-display on`.
#
# When the shell woke the displays but our watcher did not see the same event,
# nothing re-blanked and the panel sat lit on the lock screen indefinitely --
# observed 2026-09-10, DP-6 on for hours with the shell logging
# "idle-monitor: active" + "process-start: wake" at 16:30 and 17:42 while this
# daemon logged nothing at all.
#
# So instead of trying to observe every possible waker, poll the thing we
# actually care about: is the panel on while the session is locked? That covers
# the shell, our own scripts, and anything else, without having to know about
# them.
panel_is_on() {
  hyprctl monitors -j 2>/dev/null \
    | jq -e --arg m "$SECONDARY" 'any(.[]; .name == $m and .dpmsStatus == true)' >/dev/null 2>&1
}

do_blank() {
  exec 8>"$TV_STATE_LOCK"
  flock 8

  if ! is_dark; then
    flock -u 8
    return 1
  fi

  # Scope the DPMS to the secondary only. HDMI-A-2 is deliberately left alone:
  # the TV is still fully powered here, so cutting its HDMI signal makes it show
  # a "No Signal" banner instead of going quiet.
  hyprctl dispatch "hl.dsp.dpms({ action = \"disable\", monitor = \"$SECONDARY\" })" >/dev/null 2>&1
  BLANK_TV_FAILED=0
  local out state
  if ! out=$(timeout 15 "$BSCPYLGTV" "$TV_IP" turn_screen_off 2>&1); then
    # turn_screen_off is NOT idempotent (same as turn_screen_on, see tv-on.sh):
    # it errors when the screen is already off. Treating that as a failure kept
    # the held-dark loop retrying every 5s for a whole stream -- 2026-10-17
    # 16:03-16:46, 485 "failures" while the TV reported 'Screen Off' -- so ask
    # the TV before calling it one.
    state=$(timeout 15 "$BSCPYLGTV" "$TV_IP" get_power_state 2>/dev/null)
    case "$state" in
      *"'state': 'Screen Off'"*) ;;
      *)
        BLANK_TV_FAILED=1
        log "WARN: turn_screen_off failed (state: ${state:-unreachable}; ${out##*$'\n'})"
        ;;
    esac
  fi

  flock -u 8
  return 0
}

tv_blank_loop() {
  # tv_awake is STICKY on purpose. panel_is_on only reports DP-6's DPMS state,
  # but the action taken on a wake (tv-on.sh) turns the TV on -- a different
  # device whose screen state DPMS does not describe at all. Resetting on
  # panel_is_on alone let the obligation to re-blank evaporate:
  #
  #   2026-09-15 04:07  deep idle -- TV powered off
  #   2026-09-15 10:14  panel woke -> tv-on.sh ran, TV back ON, 90s timer armed
  #                     DP-6 went dark again within the grace, timer reset,
  #                     do_blank never ran, turn_screen_off never sent
  #   ...               TV sat lit on the lock screen until 11:05
  #
  # Once we wake the TV we owe it a blank, and only an unlock or an actual
  # re-blank may clear that debt.
  local awake_since=0 tv_awake=0 last_verify=0 state verify_every
  last_verify=$(date +%s)

  log "idle/locked -- blanking panel (TV stays powered)"

  # Sending turn_screen_off while the lock surface is still configuring on
  # HDMI-A-2 triggers a renegotiation that undoes the blank.
  sleep "$BLANK_SETTLE_SECS"

  if ! do_blank; then
    log "blank aborted -- activity/unlock during the ${BLANK_SETTLE_SECS}s settle"
    return
  fi

  while is_dark; do
    sleep "$BLANK_POLL_SECS"
    is_dark || break

    # While held, the shell's own wake (omarchy-system-wake on activity)
    # turns DP-6 back on in response to STREAM input. Nobody is at the desk:
    # put it straight back out instead of waking the TV for the 90s grace.
    if is_held && { panel_is_on || (( tv_awake )); }; then
      log "panel woke while held dark -- re-blanking"
      do_blank
      awake_since=0
      # Starting a stream adds the headless output, and that modeset
      # renegotiates HDMI -- the TV lights up and is unresponsive to WebOS for
      # a while (2026-10-17: lit 13:52-13:56 until the 5-min verify caught
      # it). Keep the debt and retry next pass until the TV takes it.
      tv_awake=$BLANK_TV_FAILED
      continue
    fi

    if panel_is_on || (( tv_awake )); then
      if (( awake_since == 0 )); then
        awake_since=$(date +%s)
        tv_awake=1
        log "panel woke while still locked -- re-blanking in ${REBLANK_GRACE_SECS}s unless unlocked"
        # The shell turns the panel back on but knows nothing about the TV, so
        # bring the TV screen back too -- otherwise there is a lock screen on
        # DP-6 and a black TV to type the password into.
        "$HOME/.local/lgpowercontrol/tv-on.sh" >/dev/null 2>&1 &
      elif (( $(date +%s) - awake_since >= REBLANK_GRACE_SECS )); then
        if do_blank; then
          log "re-blanked"
          awake_since=0
          tv_awake=0
        else
          # Unlocked mid-blank; the main loop's tv_restore owns it now.
          break
        fi
      fi
    else
      awake_since=0

      # Safety net: we believe the screen is off, so confirm it with the TV.
      # Three separate bugs have now left this panel lit overnight (a phantom
      # wake, a watcher that missed the shell's own wake, and a re-blank
      # obligation that evaporated), each a different hole in the event logic.
      # This does not care why the screen is on -- only that it should not be.
      # Check far more often mid-stream: nobody is at the desk to notice a lit
      # panel, and stream start/stop are exactly when the TV gets re-lit.
      verify_every=$TV_VERIFY_SECS
      is_held && verify_every=$STREAM_VERIFY_SECS
      if (( $(date +%s) - last_verify >= verify_every )); then
        last_verify=$(date +%s)
        state=$(timeout 15 "$BSCPYLGTV" "$TV_IP" get_power_state 2>/dev/null)
        case "$state" in
          *"'state': 'Active'"*)
            log "VERIFY: TV screen is on while locked -- blanking again"
            do_blank && log "re-blanked (verify)"
            ;;
        esac
      fi
    fi
  done
}

tv_deep_off() {
  log "deep idle -- powering TV off"
  exec 8>"$TV_STATE_LOCK"
  flock 8

  local out rc attempt state

  # What state is it actually in before we try? Every previous diagnosis here
  # was wrong because this was not recorded.
  state=$(timeout 15 "$BSCPYLGTV" "$TV_IP" get_power_state 2>/dev/null) \
    && log "pre power_off state: $state" \
    || log "pre power_off: TV not reachable"

  # WebOS answers "Try Again Later (EWS)" and closes the socket with 1008 when
  # it is not ready to serve a new client. Observed failing on every deep-off
  # from 2026-09-17 onward, with the connection refused before power_off was
  # ever sent -- so the TV never powered down, kept accumulating panel hours,
  # and started prompting for OLED pixel refresh on unlock. It is literally
  # asking us to retry, so retry.
  rc=1
  for attempt in 1 2 3; do
    out=$(timeout 30 "$BSCPYLGTV" "$TV_IP" power_off 2>&1)
    rc=$?
    (( rc == 0 )) && break
    log "power_off attempt $attempt failed; retrying in 5s"
    sleep 5
  done

  if (( rc != 0 )); then
    # Last resort: WoL brings the WebOS service back to a state where it will
    # accept a client, then power it off for real. Only reached when the plain
    # retries could not connect at all.
    log "power_off still failing -- waking the service with WoL, then retrying"
    wakeonlan -i "$TV_IP" "$TV_MAC" >/dev/null 2>&1
    sleep 10
    out=$(timeout 30 "$BSCPYLGTV" "$TV_IP" power_off 2>&1)
    rc=$?
  fi

  sleep 5
  if state=$(timeout 15 "$BSCPYLGTV" "$TV_IP" get_power_state 2>/dev/null); then
    case "$state" in
      *"'state': 'Active'"*)
        # Reachable and still lit. Powering off did not take, so at minimum get
        # the pixels dark rather than leave a bright panel on the lock screen.
        log "WARN: TV still Active after power_off -- falling back to turn_screen_off"
        timeout 15 "$BSCPYLGTV" "$TV_IP" turn_screen_off >/dev/null 2>&1 ||
          log "WARN: turn_screen_off fallback also failed"
        ;;
      *)
        log "post power_off state: $state"
        ;;
    esac
  elif (( rc == 0 )); then
    log "TV unreachable after a successful power_off, as expected when it powers down"
  else
    # Do NOT call this success. An unreachable TV looks identical whether it
    # powered down or is merely refusing connections with the screen off, and
    # reporting the latter as success is what hid this bug for days.
    log "WARN: power_off failed AND the TV is unreachable -- power state unknown"
  fi

  flock -u 8
}

tv_restore() {
  log "active -- restoring displays"
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

# --- activity monitor -----------------------------------------------------
# Separate 3s IdleMonitor so the first real input after a stream ends is seen
# immediately, rather than waiting on the shell's 5-minute idle.
rm -f "$HOLD_FILE" "$ACTIVITY_FILE"
quickshell -p "$HOME/.local/lgpowercontrol/activity-monitor/shell.qml" 2>&1 |
  while IFS= read -r line; do
    case "$line" in
    *"ACTIVITY idle"*) echo idle >"$ACTIVITY_FILE" ;;
    *"ACTIVITY active"*) echo active >"$ACTIVITY_FILE" ;;
    esac
  done &

activity() { cat "$ACTIVITY_FILE" 2>/dev/null; }

# --- state machine ---------------------------------------------------------
dark=0
dark_at=0
post_stream_quiet=0
escalated=0

log "started (poll=${POLL_SECS}s, deep-off after ${DEEP_AFTER_DARK_SECS}s dark)"

while true; do
  # Evaluated BEFORE is_dark: sunshine-stream-begin creates the flag and output
  # as a prep-cmd, before the client sends any input that would end idle.
  if is_streaming; then
    if (( dark )) && ! is_held; then
      touch "$HOLD_FILE"
      log "stream started with displays dark -- holding them dark"
    fi
    post_stream_quiet=0
  elif is_held; then
    # Stream is over. Release only on input that cannot be the stream's: wait
    # for the stream's input to go quiet, then for input to start again.
    if [[ $(activity) == idle ]]; then
      post_stream_quiet=1
    elif (( post_stream_quiet )) && [[ $(activity) == active ]]; then
      rm -f "$HOLD_FILE"
      post_stream_quiet=0
      log "input at the desk after stream -- releasing hold"
    fi
  fi

  if is_dark; then
    if (( ! dark )); then
      dark=1
      dark_at=$(date +%s)
      escalated=0
      tv_blank_loop &
    elif (( ! escalated && DEEP_AFTER_DARK_SECS > 0 )); then
      if (( $(date +%s) - dark_at >= DEEP_AFTER_DARK_SECS )); then
        escalated=1
        tv_deep_off
      fi
    fi
  else
    if (( dark )); then
      dark=0
      escalated=0
      tv_restore
    fi
  fi

  sleep "$POLL_SECS"
done
