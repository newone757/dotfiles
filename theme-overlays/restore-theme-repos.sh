#!/usr/bin/env bash
# Re-create the symlinked theme clones and apply local overlays.
#
# Omarchy 4 refuses to stage any .lua, terminal config, or vscode.json from a
# theme it considers "from a git repo". The test is one predicate in
# omarchy-theme-set:
#
#   theme_came_from_a_repo() { [[ ! -L $source && -d $source/.git ]]; }
#
# So a clone that lives elsewhere and is SYMLINKED into ~/.config/omarchy/themes
# is trusted and staged in full -- window shapes included -- while `git pull`
# keeps working. `omarchy theme install` clones straight into the themes dir, so
# any theme installed that way needs converting again afterwards.
#
# Audit a theme's hyprland.lua before converting it: Hyprland executes that Lua.
# The ones listed in themes.tsv were checked and are purely declarative
# (hl.config, hl.window_rule, hl.animation, hl.curve, hl.layer_rule).
set -euo pipefail

REPO_DIR="$HOME/.local/share/omarchy-theme-repos"
THEMES_DIR="$HOME/.config/omarchy/themes"
OVERLAY_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$REPO_DIR" "$THEMES_DIR"

while IFS=$'\t' read -r name url; do
  [[ -n ${name:-} && ${name:0:1} != "#" ]] || continue
  target="$REPO_DIR/$name"

  if [[ ! -d $target ]]; then
    echo "Cloning $name"
    git clone --quiet -- "$url" "$target" || { echo "  failed: $url" >&2; continue; }
  fi

  # A real directory here would shadow the symlink and be treated as a repo.
  if [[ -e $THEMES_DIR/$name && ! -L $THEMES_DIR/$name ]]; then
    rm -rf "$THEMES_DIR/$name"
  fi
  ln -nsf "$target" "$THEMES_DIR/$name"

  # Overlays add files upstream does not ship (see README.md).
  if [[ -d $OVERLAY_DIR/$name ]]; then
    cp -f "$OVERLAY_DIR/$name"/* "$target/"
    echo "  applied overlay for $name"
  fi
done < "$OVERLAY_DIR/themes.tsv"

echo "Done. Re-apply with: omarchy theme set <name>"
