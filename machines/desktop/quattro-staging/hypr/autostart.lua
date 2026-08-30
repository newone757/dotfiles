-- Extra autostart processes, ported from Omarchy 3.8.4 autostart.conf.
-- Staged 2026-08-30, BEFORE the Quattro upgrade. Not yet live.

-- Apple Magic Trackpad 3-finger gesture daemon.
-- The systemd user unit (~/.config/systemd/user/trackpad-gestures.service) is
-- independent of the compositor and should survive the upgrade untouched, so
-- this stays a plain systemctl start rather than an o.launch_on_start.
o.launch_on_start("systemctl --user start trackpad-gestures.service")

-- Auto-tile: float the first window per workspace, tile when a second opens.
-- VERIFY AFTER UPGRADE: this script drives hyprctl and parses window state.
-- Hyprland 0.56 changed `hyprctl binds` JSON output, and Quattro adds its own
-- window rules. Test before trusting.
o.launch_on_start("~/.local/bin/auto-tile")

------------------------------------------------------------------------------
-- RETIRED / NEEDS DECISION
------------------------------------------------------------------------------
-- screensaver-inhibit-watch
--   Old line: exec-once = python3 ~/.local/bin/screensaver-inhibit-watch
--
--   This daemon OWNS the org.freedesktop.ScreenSaver D-Bus name so that browser
--   Video Wake Locks could suppress hypridle (your hypridle.conf set
--   ignore_dbus_inhibit = true and delegated to this instead).
--
--   In Quattro, idle detection lives inside the Quickshell shell process and
--   has its own inhibitor handling. Two problems:
--     1. It may be redundant.
--     2. Worse, it may CONFLICT — your lgpowercontrol-dbus-events.sh listens on
--        org.freedesktop.ScreenSaver, and if this daemon still owns that name,
--        it can intercept the signals the TV control depends on.
--
--   DO NOT enable this on first boot. Bring the system up without it, confirm
--   idle + lock + TV control all behave, and only then decide whether it earns
--   its place back.
--
-- o.launch_on_start("python3 ~/.local/bin/screensaver-inhibit-watch")
