#!/usr/bin/env bash
# Dotfiles setup — symlinks configs for the current machine into ~/.
# Usage: ./setup.sh [machine]
#   machine defaults to the hostname (macbook-pro or desktop)
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
MACHINE="${1:-$(hostname -s)}"
MACHINE_DIR="$DOTFILES_DIR/machines/$MACHINE"
COMMON_DIR="$DOTFILES_DIR/common"

if ! command -v stow &>/dev/null; then
  echo "error: GNU stow is required. Install with: sudo pacman -S stow  (or brew install stow on macOS)"
  exit 1
fi

if [[ ! -d "$MACHINE_DIR" ]]; then
  echo "error: no config directory found for machine '$MACHINE' (expected $MACHINE_DIR)"
  echo "Available machines: $(ls "$DOTFILES_DIR/machines/")"
  exit 1
fi

echo "Stowing common config..."
if [[ -n "$(ls -A "$COMMON_DIR" 2>/dev/null)" ]]; then
  stow --dir="$DOTFILES_DIR" --target="$HOME" common
fi

echo "Stowing machine config for '$MACHINE'..."
stow --dir="$DOTFILES_DIR/machines" --target="$HOME" "$MACHINE"

echo "Done. You may need to log out and back in for all changes to take effect."

# Theme clones live outside the repo (they are upstream git repos) and must be
# symlinked into ~/.config/omarchy/themes or Omarchy strips their .lua.
if [[ -x "$DOTFILES_DIR/theme-overlays/restore-theme-repos.sh" ]]; then
  echo "Restoring symlinked theme repos..."
  "$DOTFILES_DIR/theme-overlays/restore-theme-repos.sh" || echo "  (skipped; re-run manually)"
fi
