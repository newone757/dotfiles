-- Personal keybinding overrides, ported from Omarchy 3.8.4 bindings.conf.
-- Staged 2026-08-30, BEFORE the Quattro upgrade. Not yet live.
--
-- IMPORTANT: ~21 of your 3.8.x custom bindings became Omarchy 4 DEFAULTS and
-- are deliberately NOT repeated here. See bindings-AUDIT.md for the full list.
-- Adding them back would be redundant, not harmful, but keeping this file
-- small is the point: less to re-port at the next major version.

------------------------------------------------------------------------------
-- 1. Web apps that differ from the Quattro defaults
------------------------------------------------------------------------------

-- Quattro binds SUPER+SHIFT+A to ChatGPT; you use Claude.
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Claude", { webapp = "https://claude.ai/" })

-- Not in Quattro defaults at all — purely yours.
o.bind("SUPER + SHIFT + R", "Reddit", { webapp = "https://reddit.com" })
o.bind("SUPER + SHIFT + H", "Home", { webapp = "http://10.0.1.10:5050" })

------------------------------------------------------------------------------
-- 2. Window management preferences
------------------------------------------------------------------------------

-- You close windows with SUPER+Q, not Quattro's default SUPER+W.
hl.unbind("SUPER + W")
o.bind("SUPER + Q", "Close window", hl.dsp.window.close())

------------------------------------------------------------------------------
-- 3. Activity monitor
------------------------------------------------------------------------------
-- Quattro binds SUPER+T to float/tile toggle, so your old SUPER+SHIFT+T for
-- btop is free. Confirm SUPER+SHIFT+T is unbound after upgrade before trusting.
o.bind("SUPER + SHIFT + T", "Activity", { tui = "btop", focus = true })

------------------------------------------------------------------------------
-- 4. LG TV power control
------------------------------------------------------------------------------
-- These call the rewritten scripts (see quattro-staging/lgpowercontrol/).
-- The old inline bash used `pgrep -x hyprlock`, which is DEAD in Quattro —
-- hyprlock is uninstalled. Lock state now comes from
-- `omarchy-hyprland-session-locked`.

o.bind("SUPER + SHIFT + K", "TV on", "~/.local/lgpowercontrol/tv-on.sh")
o.bind("SUPER + SHIFT + L", "TV off", "~/.local/lgpowercontrol/tv-off.sh")

-- Lock + blank the TV. Quattro's own lock is SUPER+CTRL+L; this is the variant
-- that also powers down the panel.
-- NOTE: SUPER+L is "Toggle workspace layout" in Quattro by default (which is
-- exactly what you had rebound SUPER+CTRL+L to). Decide which you want:
--   (a) keep SUPER+L as lock+TV-off  -> unbind below stays
--   (b) accept Quattro's SUPER+L layout toggle -> delete this block, move
--       lock+TV-off to SUPER+GRAVE only
hl.unbind("SUPER + L")
o.bind("SUPER + L", "Lock + TV off", "~/.local/lgpowercontrol/lock-and-blank.sh")
o.bind("SUPER + GRAVE", "Lock + TV off", "~/.local/lgpowercontrol/lock-and-blank.sh")

------------------------------------------------------------------------------
-- 5. RETIRED — do not restore
------------------------------------------------------------------------------
-- SUPER+CTRL+SHIFT+I  "Restart idle daemon"
--   hypridle no longer exists; idle lives in the Quickshell process.
--   Quattro's SUPER+CTRL+I is "Toggle locking on idle" (stay-awake).
--
-- SUPER+CTRL+L "Toggle workspace layout"
--   Now SUPER+L by default, AND SUPER+CTRL+L is Quattro's lock binding.
--   Leaving your old override in place would shadow the lock screen.
--
-- The trailing "Alt+Scroll to cycle browser tabs" comment in your old
-- bindings.conf had no binding under it. Nothing to port.
