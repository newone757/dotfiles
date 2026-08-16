#!/bin/bash
TV_IP=10.0.1.28
MAC=00:a1:59:35:35:da
BSCPYLGTV=/home/lonnie/.local/lgpowercontrol/bscpylgtv/bin/bscpylgtvcommand

tv_up() {
    $BSCPYLGTV $TV_IP get_inputs True >/dev/null 2>&1
}

# Blast 3 WoLs immediately — covers all sleep depths
wakeonlan $MAC >/dev/null; sleep 0.3
wakeonlan $MAC >/dev/null; sleep 0.3
wakeonlan $MAC >/dev/null

# Minimum wait regardless of tv_up — WebOS port 3000 stays alive in soft standby,
# so tv_up can return true instantly before the TV is HDMI-ready
sleep 4

# For fully-off TVs that need longer to boot, poll up to 10 more seconds
for i in 1 2 3 4 5 6 7 8 9 10; do
    tv_up && break
    sleep 1
done

# DPMS cycle to force HDMI renegotiation
hyprctl dispatch dpms off HDMI-A-2
sleep 1
hyprctl dispatch dpms on HDMI-A-2
