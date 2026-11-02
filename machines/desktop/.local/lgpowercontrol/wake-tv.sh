#!/bin/bash
# Wake LG TV (10.0.1.28, MAC 00:a1:59:35:35:da) and re-handshake its HDMI link
wakeonlan 00:a1:59:35:35:da
sleep 5
TV=$(~/.local/bin/display-name tv)
hyprctl keyword monitor "$TV,disable"
sleep 1
hyprctl keyword monitor "$TV,3840x2160@120,0x0,1"
