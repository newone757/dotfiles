-- Display layout, ported from Omarchy 3.8.4 monitors.conf.
-- Staged 2026-08-30, BEFORE the Quattro upgrade. Not yet live.

local displays = require("hypr.displays")

-- 1x scaling — your displays are not retina-class.
hl.env("GDK_SCALE", "1")

-- Fallback for anything not named below.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- LG TV, primary, 4K120.
hl.monitor({ output = displays.tv, mode = "3840x2160@120", position = "0x0", scale = 1 })

-- Biomedical Systems Laboratory L2 touch strip, sits below the TV.
-- 2160 = the TV's height, so this stacks directly underneath;
-- 960 = (3840 - 1920) / 2, centering it horizontally.
hl.monitor({ output = displays.panel, mode = "1920x720", position = "960x2160", scale = 1 })

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

------------------------------------------------------------------------------
-- Workspace pinning (ported 2026-08-30, post-upgrade)
------------------------------------------------------------------------------
-- The 4.0.1 Lua API exposes hl.workspace_rule (confirmed by runtime
-- introspection of the `hl` table; it is a Hyprland built-in, not an Omarchy
-- helper, which is why it appears nowhere in /usr/share/omarchy).
--
-- Equivalent to the 3.8.4 hyprland.conf lines:
--   workspace = 1, monitor:HDMI-A-2, default:true
for _, ws in ipairs({ 1, 2, 3, 4, 5 }) do
  hl.workspace_rule({ workspace = tostring(ws), monitor = displays.tv, default = ws == 1 })
end

-- The panel is 1920x720, so the single-window square aspect toggle (SUPER+CTRL+
-- BACKSPACE) would squeeze a lone window there to 720x720. Hyprland 0.56 ignores
-- that option in layout_opts, but the scrolling layout doesn't apply it at all,
-- so the panel's workspace uses scrolling (tested 2026-11-03).
hl.workspace_rule({
  workspace = "6",
  monitor = displays.panel,
  default = true,
  layout = "scrolling",
})

-- Sunshine stream workspace. Lives on the headless "sunshine" output that
-- ~/.local/bin/sunshine-virtual-display creates per stream; harmless when that
-- output doesn't exist.
hl.workspace_rule({ workspace = "name:stream", monitor = "sunshine", default = true })

-- Keep XWayland's primary output on the TV (or the Sunshine output mid-stream).
-- When the TV re-enumerates after the panel, XWayland lists the panel first and Proton
-- games come up at 1920x720. The short delay lets XWayland see the new layout.
for _, ev in ipairs({ "monitor.added", "monitor.removed", "monitor.layout_changed" }) do
  hl.on(ev, function()
    hl.exec_cmd("sleep 1; ~/.local/bin/xwayland-primary")
  end)
end
