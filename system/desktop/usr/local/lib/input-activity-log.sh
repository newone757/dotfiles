#!/bin/bash
# Logs WHICH input device produced activity, so phantom wakes of the displays
# (lgpowercontrol, 2026-10-17: shell went "active" at 20:33/21:53/22:40/22:55
# with nobody at the desk) can be traced to a device.
#
# Runs as root (system unit input-activity-log.service) so the user never needs
# read access to /dev/input. Logs device name + event type only, at most one
# line per device per 10s; key codes are never logged (libinput obscures them
# without --show-keycodes). Read it with:
#   journalctl -t input-activity --since today
exec libinput debug-events 2>&1 | gawk '
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
    now = systime()
    if (now - last[dev] >= 10) {
      last[dev] = now
      print "input: " (dev in name ? name[dev] : dev) " [" type "]"
      fflush()
    }
  }
'
