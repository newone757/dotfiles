-- Display layout, ported from Omarchy 3.8.4 monitors.conf.
-- Staged 2026-08-30, BEFORE the Quattro upgrade. Not yet live.

-- 1x scaling — your displays are not retina-class.
hl.env("GDK_SCALE", "1")

-- Fallback for anything not named below.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- LG TV, primary, 4K120.
hl.monitor({ output = "HDMI-A-2", mode = "3840x2160@120", position = "0x0", scale = 1 })

-- Biomedical Systems Laboratory L2 touch strip, sits below the TV.
-- 2160 = the TV's height, so this stacks directly underneath;
-- 960 = (3840 - 1920) / 2, centering it horizontally.
hl.monitor({ output = "DP-6", mode = "1920x720", position = "960x2160", scale = 1 })

------------------------------------------------------------------------------
-- Workspace pinning — VERIFY SYNTAX AFTER UPGRADE
------------------------------------------------------------------------------
-- In 3.8.4 these lived in hyprland.conf as:
--   workspace = 1, monitor:HDMI-A-2, default:true
--   workspace = 2..5, monitor:HDMI-A-2, default:false
--   workspace = 6, monitor:DP-6, default:true
--
-- The Quattro manual says workspace rules belong in monitors.lua, but ships no
-- example and no `hl.workspace` helper appears in the 4.0.1 Lua tree. I did NOT
-- guess at the call signature.
--
-- After upgrading, check the real API with:
--   grep -rn "workspace" /usr/share/omarchy/default/hypr/*.lua
--   ls /usr/share/omarchy/manual/33-monitors.md
-- then port the six rules above. Until you do, workspaces will land on
-- whichever monitor has focus — annoying, not broken.
