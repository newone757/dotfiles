-- Personal input overrides, ported from Omarchy 3.8.4 input.conf.
-- Staged 2026-08-30, BEFORE the Quattro upgrade. Not yet live.

local displays = require("hypr.displays")

-- Quattro's defaults already set: kb_options compose:caps (plus
-- shift:both_capslock_cancel), repeat_rate 40, numlock_by_default true,
-- clickfinger_behavior true, scroll_factor 0.4. Only genuine differences
-- from those defaults are listed here.
hl.config({
  input = {
    -- Quattro default is 250; you run 600.
    repeat_delay = 600,

    touchpad = {
      -- Quattro default is false; you use natural scrolling.
      natural_scroll = true,
    },

    -- Map the touchscreen to the secondary panel.
    touchdevice = {
      output = displays.panel,
    },
  },
})

-- Terminal scroll speeds. These match Quattro's defaults exactly, so they are
-- commented out — uncomment only if the defaults change under you.
-- o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
-- o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })

-- Four-finger horizontal swipe to change workspaces.
-- NOTE: Quattro's commented example uses fingers = 3. You were on 4.
-- Also note your trackpad-gestures daemon binds 3-finger gestures separately,
-- so keeping this at 4 avoids fighting it.
--
-- On a workspace using the scrolling layout (the panel's workspace 6), the same
-- swipe slides the columns instead. Switching workspaces there is pointless,
-- since the panel only has one. The gesture is re-registered whenever the active
-- workspace or monitor changes; "unset" clears the previous one first.
local swipe_action
local function update_swipe()
  local ws = hl.get_active_workspace()
  local action = (ws and ws.tiled_layout == "scrolling") and "scroll_move" or "workspace"
  if action == swipe_action then return end
  if swipe_action then
    hl.gesture({ fingers = 4, direction = "horizontal", action = "unset" })
  end
  swipe_action = action
  hl.gesture({ fingers = 4, direction = "horizontal", action = action })
end
update_swipe()
hl.on("workspace.active", update_swipe)
hl.on("monitor.focused", update_swipe)

-- Per-device settings.
-- VERIFY AFTER UPGRADE: the touchscreen is not currently enumerating (dead USB
-- cable, not a config problem — see the upgrade plan). Once it comes back,
-- confirm the device name is still exactly this with `hyprctl devices`.
hl.device({ name = "bjyp-l2-device-bjyp-l2-v1.10", output = displays.panel })

hl.device({ name = "apple-inc.-magic-trackpad", sensitivity = 0.4 })
hl.device({ name = "apple-inc.-magic-trackpad-1", sensitivity = 0.4 })
