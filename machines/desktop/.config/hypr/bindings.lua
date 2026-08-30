-- Personal keybinding overrides, ported from Omarchy 3.8.4 bindings.conf.
-- Staged 2026-08-30, BEFORE the Quattro upgrade. Not yet live.
-- Collision decisions made 2026-08-30 (see bindings-AUDIT.md for the reasoning).
--
-- ~21 of the old custom bindings became Omarchy 4 defaults and are deliberately
-- NOT repeated here. Keeping this file small is the point: less to re-port at
-- the next major version.

------------------------------------------------------------------------------
-- 1. Web apps
------------------------------------------------------------------------------

-- DECIDED: Claude wins SUPER+SHIFT+A. Quattro's default is ChatGPT, which is
-- left without a binding. Add one on a free chord if you ever want it back.
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Claude", { webapp = "https://claude.ai/" })

-- Not Quattro defaults; no collisions.
o.bind("SUPER + SHIFT + R", "Reddit", { webapp = "https://reddit.com" })
o.bind("SUPER + SHIFT + H", "Home", { webapp = "http://10.0.1.10:5050" })

------------------------------------------------------------------------------
-- 2. Window management
------------------------------------------------------------------------------

-- DECIDED: close on SUPER+Q, not Quattro's SUPER+W.
hl.unbind("SUPER + W")
o.bind("SUPER + Q", "Close window", hl.dsp.window.close())

------------------------------------------------------------------------------
-- 3. LG TV power control
------------------------------------------------------------------------------
-- DECIDED: full stock on the L keys. Quattro keeps
--   SUPER + L         Toggle workspace layout
--   SUPER + CTRL + L  Lock system
-- and neither is overridden here.
--
-- IMPORTANT CONSEQUENCE: SUPER+CTRL+L is now a PLAIN lock. It does not know
-- about the TV. The same is true of every other lock path — idle timeout, the
-- system menu, `omarchy system lock`.
--
-- The fix is NOT to override the binding. It's to drive TV power from the
-- LOCK EVENT rather than from a keystroke, so every lock path behaves the
-- same. That's lgpowercontrol-dbus-events.sh listening on
-- org.freedesktop.ScreenSaver — it already works this way today and is
-- compositor-independent, which is exactly why it should survive Quattro.
--
-- Verify after upgrading:
--   1. Press SUPER+CTRL+L
--   2. journalctl -t lgpowercontrol-dbus-events -f
--   3. The TV should power down with no keybinding involved.
-- If the Quickshell lock does NOT emit ScreenSaver signals, fall back to
-- polling `omarchy-hyprland-session-locked` from that same daemon.

-- Manual overrides, for when you want to act on the TV without locking.
o.bind("SUPER + SHIFT + K", "TV on", "~/.local/lgpowercontrol/tv-on.sh")
o.bind("SUPER + SHIFT + L", "TV off", "~/.local/lgpowercontrol/tv-off.sh")

-- Explicit lock + TV off. Redundant once the D-Bus path above is confirmed
-- working, but harmless, and a useful fallback while you're verifying it.
o.bind("SUPER + GRAVE", "Lock + TV off", "~/.local/lgpowercontrol/lock-and-blank.sh")

------------------------------------------------------------------------------
-- 4. RETIRED — do not restore
------------------------------------------------------------------------------
-- SUPER+CTRL+SHIFT+I  "Restart idle daemon"
--   hypridle no longer exists; idle lives in the Quickshell process.
--   Quattro's SUPER+CTRL+I is "Toggle locking on idle" (stay-awake).
--
-- SUPER+CTRL+L  "Toggle workspace layout"  -> now Quattro's Lock system
-- SUPER+L       "Lock + TV off"            -> now Quattro's layout toggle
--   Both dropped by decision. Upstream and you had swapped the same pair;
--   taking stock means zero overrides on these keys.
--
-- SUPER+SHIFT+T  "Activity" (btop)
--   Dropped by decision in favour of Quattro's SUPER+CTRL+T, which fits its
--   SUPER+CTRL+* family for system panels (Audio, Display, Network, Power).
--
-- The trailing "Alt+Scroll to cycle browser tabs" comment in the old
-- bindings.conf had no binding under it. Nothing to port.
