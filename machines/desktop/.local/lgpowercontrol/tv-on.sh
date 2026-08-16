#!/bin/bash
# Turn TV on. Fast path: TV is screen-blanked but still fully powered
# (turn_screen_on is instant, no WoL race). Falls back to full WoL +
# HDMI handshake sequence if the TV is actually powered off.
BSCPYLGTV=/home/lonnie/.local/lgpowercontrol/bscpylgtv/bin/bscpylgtvcommand
TV_IP=10.0.1.28

# Can be called more than once per wake (activity-watcher + unlock fallback
# both fire). Serialize concurrent calls...
exec 9>/tmp/tv-on.lock
flock -n 9 || exit 0

# ...and check state before acting: turn_screen_on hard-errors (errorCode
# -102, "current sub state must be 'screen off'") if the TV is already
# Active — it is NOT idempotent. Without this check, a redundant call right
# after the TV's already on would fail its fast path and fall through to
# the WoL+DPMS-flash sequence for no reason.
STATE=$(timeout 3 $BSCPYLGTV $TV_IP get_power_state 2>/dev/null)

case "$STATE" in
*"'state': 'Active'"*)
    exit 0
    ;;
*"'state': 'Screen Off'"*)
    timeout 3 $BSCPYLGTV $TV_IP turn_screen_on >/dev/null 2>&1
    exit 0
    ;;
esac

~/.local/lgpowercontrol/wake-hdmi.sh
