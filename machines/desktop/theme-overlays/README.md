# Theme overlays

Files added on top of upstream theme repos, kept here because they live inside
git clones in `~/.local/share/omarchy-theme-repos/` and would be lost on a
re-clone.

Omarchy 4 loads a theme's `hyprland.lua` via
`require_optional.module("omarchy.current.theme.hyprland")` in
`/usr/share/omarchy/default/hypr/omarchy.lua`, resolved against
`~/.local/state/omarchy/current/theme/`. So it applies **only while that theme
is active** and reverts on switch — the right place for per-theme window shapes,
as opposed to `~/.config/hypr/looknfeel.lua`, which is global.

Two prerequisites:

1. The theme directory must be a symlink (or non-git), or `omarchy-theme-set`
   refuses to stage any `.lua` from it. See `theme_came_from_a_repo()`.
2. A theme that ships `hyprland.lua` skips the generated border-colour template
   (`omarchy-theme-set-templates`: `if [[ ! -f $output_path ]]`), so the overlay
   must include the border colours itself.

## koyanagi

Upstream ships colours only. The author's full look lives in a separate
`koyanagi-config` repo whose `install.sh` overwrites `~/.config/hypr/looknfeel.lua`
— making the look global and hardcoding koyanagi's grey borders over every other
theme. This overlay carries the same values, scoped to the theme.
