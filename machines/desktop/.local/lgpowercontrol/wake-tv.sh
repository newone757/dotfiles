#!/bin/bash
# Wake LG TV (10.0.1.28, MAC 00:a1:59:35:35:da) and re-handshake HDMI-A-2
wakeonlan 00:a1:59:35:35:da
sleep 5
hyprctl keyword monitor HDMI-A-2,disable
sleep 1
hyprctl keyword monitor "HDMI-A-2,3840x2160@120,0x0,1"
