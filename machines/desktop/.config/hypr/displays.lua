-- The two physical displays, matched by EDID description instead of connector
-- name. Connector numbers are shared across GPUs and assigned in driver load
-- order, so with the 7800X3D's iGPU enabled the same 3080 ports have come up as
-- HDMI-A-2/DP-6 on one install and HDMI-A-1/DP-3 on the next (2026-11-02).
-- Shell scripts resolve these with ~/.local/bin/display-name.
--
-- Check the descriptions with: hyprctl monitors all
return {
  -- LG TV, primary, 4K120.
  tv = "desc:LG Electronics LG TV SSCR2 0x01010101",
  -- Biomedical Systems Laboratory L2 touch strip under the TV.
  panel = "desc:Biomedical Systems Laboratory L2 L2-20230810",
}
