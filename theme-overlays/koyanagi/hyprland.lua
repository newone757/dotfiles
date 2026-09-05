-- Koyanagi — window shapes and effects, scoped to this theme.
--
-- The upstream theme repo ships colours only; the author's "full" look lives in
-- a separate koyanagi-config repo whose install.sh OVERWRITES
-- ~/.config/hypr/looknfeel.lua. That makes the look global: it would follow you
-- into every other theme and hardcode koyanagi's grey borders over theirs.
--
-- This file does the same job the way Quattro intends. omarchy.lua does
--   require_optional.module("omarchy.current.theme.hyprland")
-- against ~/.local/state/omarchy/current/theme/, so it loads ONLY while this
-- theme is active and everything reverts to Omarchy defaults on switch.
--
-- It also loads BEFORE ~/.config/hypr/looknfeel.lua, so any personal override
-- there still wins over anything set here.
--
-- Values from koyanagi-config install.sh. Border colours are the ones Omarchy
-- generated from this theme's colors.toml — reproduced here because a theme
-- that ships hyprland.lua skips the generated template entirely
-- (omarchy-theme-set-templates: `if [[ ! -f $output_path ]]`).

local active_border_color = { colors = { "#D8D8D8", "#F0F0F0", "#FFFFFF", "#C8C8C8" }, angle = 45 }
local inactive_border_color = "rgba(808080aa)"

hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 6,
    border_size = 1,

    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  decoration = {
    rounding = 10,

    shadow = {
      enabled = true,
      range = 30,
      render_power = 4,
      color = "rgba(00000055)",
      color_inactive = "rgba(00000033)",
      offset = "0 4",
    },

    blur = {
      enabled = true,
      size = 12,
      passes = 4,
      contrast = 1.2,
      brightness = 0.9,
      vibrancy = 0.4,
      vibrancy_darkness = 0.3,
      noise = 0.12,
      ignore_opacity = true,
    },

    -- Upstream koyanagi-config sets active 0.75 / inactive 0.65, which reads
    -- as every window being faded rather than as depth. Dialled back to a hint:
    -- the focused window is all but solid, and unfocused ones sit back slightly.
    -- Raise toward 1.0 for less, lower for more.
    active_opacity = 0.95,
    inactive_opacity = 0.90,
    fullscreen_opacity = 1.0,
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },
})

-- Blur the shell surfaces so the bar/menus match the windows.
local shell_layers = {
  "omarchy-bar", "omarchy-menu", "omarchy-notifications",
  "omarchy-clipboard", "omarchy-emojis", "omarchy-osd",
  "omarchy-polkit", "omarchy-image-selector", "omarchy-reminders",
  "omarchy-network-qr", "omarchy-keyboard-panel",
}

local blur_rules = {}
for _, ns in ipairs(shell_layers) do
  table.insert(blur_rules, { rule = "blur", match = { namespace = ns } })
  table.insert(blur_rules, { rule = "ignorezero", match = { namespace = ns } })
end

hl.config({ layerrule = blur_rules })
