// Prints "idle"/"active" on a short (3s) input-idle threshold. Used by
// lgpowercontrol-daemon.sh to notice the first REAL input after a Moonlight
// stream ends, independent of the Omarchy shell's 5-minute idle timer.
// respectInhibitors is off on purpose: this is about input, not about whether
// something (a game, a video) wants the session kept awake.
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
  IdleMonitor {
    timeout: 3
    respectInhibitors: false
    onIsIdleChanged: console.info("ACTIVITY " + (isIdle ? "idle" : "active"))
    Component.onCompleted: console.info("ACTIVITY " + (isIdle ? "idle" : "active"))
  }
}
