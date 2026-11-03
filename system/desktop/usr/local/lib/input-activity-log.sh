#!/bin/bash
# Logs WHICH input device produced activity, so phantom wakes of the displays
# (lgpowercontrol, 2026-10-17: shell went "active" at 20:33/21:53/22:40/22:55
# with nobody at the desk) can be traced to a device.
#
# Runs as root (system unit input-activity-log.service) so the user never needs
# read access to /dev/input. Logs device name + event type only, at most one
# line per device per 10s. Read it with:
#   journalctl -t input-activity --since today
#
# Media/system-key devices ("Consumer Control", "System Control") are the
# exception: every key event from them is logged with its key name and code,
# unthrottled. The Lofree HYZEN67's Consumer Control device was suspected of
# sending a key with no physical press (2026-10, fix lost with the 980 PRO);
# the key code is what a hwdb rule needs to disable it. libinput runs with
# --show-keycodes for this, but codes from every other device are dropped here
# and never logged, so ordinary typing stays out of the journal.
exec libinput debug-events --show-keycodes 2>&1 | gawk '
  {
    dev = $1; sub(/^-/, "", dev)
    type = $2
  }
  type == "DEVICE_ADDED" || type == "DEVICE_REMOVED" {
    if (match($0, /DEVICE_(ADDED|REMOVED) +(.*[^ ]) +seat[0-9]/, m)) {
      if (type == "DEVICE_ADDED") name[dev] = m[2]
      if (started) { print type ": " m[2] " (" dev ")"; fflush() }
    }
    next
  }
  dev ~ /^event[0-9]+$/ {
    if (!started) { started = 1; print "watching " length(name) " devices"; fflush() }
    if (type == "KEYBOARD_KEY" && name[dev] ~ /(Consumer|System) Control/) {
      key = $0; sub(/^[^\t]*\t/, "", key)
      print "media-key: " name[dev] " (" dev ") " key
      fflush()
      last[dev] = systime()
      next
    }
    now = systime()
    if (now - last[dev] >= 10) {
      last[dev] = now
      print "input: " (dev in name ? name[dev] : dev) " [" type "]"
      fflush()
    }
  }
'
