#!/bin/bash
# Build FreeRDP's SDL3 client with the RemoteApp popup patch into
# ~/.local/opt/freerdp-sdl, without touching the system freerdp package.
#
# Why: the stock sdl-freerdp3 hides every layered RemoteApp window that is not
# next to another visible popup, assuming it is a menu shadow. Lightroom's sort
# and overflow ("...") flyouts are standalone layered popups, so they never
# appear. The patch also shows layered windows that take input; Windows' shadows
# are click-through (WS_EX_TRANSPARENT). See sdl-rail-standalone-layered-popups.patch.
#
# windows-app uses ~/.local/opt/freerdp-sdl/bin/sdl-freerdp3 when it exists.
# Re-run after a FreeRDP release that is worth having (set VERSION), or drop the
# patch once upstream handles these popups.
#
# Needs: cmake ninja (sudo pacman -S --needed cmake ninja) plus freerdp's own
# build deps, which the installed freerdp/sdl3 packages already provide.
#
# Usage: build.sh [VERSION]   (default 3.33.0)

set -euo pipefail

VERSION=${1:-3.33.0}
HERE=$(cd "$(dirname "$0")" && pwd)
WORK="$HOME/.local/src/freerdp-sdl-patched"
PREFIX="$HOME/.local/opt/freerdp-sdl"
SRC="$WORK/src/FreeRDP-$VERSION"
BUILD="$WORK/build-$VERSION"

for tool in cmake ninja; do
  command -v "$tool" >/dev/null || { echo "missing $tool: sudo pacman -S --needed cmake ninja" >&2; exit 1; }
done

mkdir -p "$WORK/dl" "$WORK/src"
tarball="$WORK/dl/freerdp-$VERSION.tar.gz"
[[ -s $tarball ]] || curl -fL -o "$tarball" "https://github.com/FreeRDP/FreeRDP/archive/refs/tags/$VERSION.tar.gz"

# Always start from a pristine tree so the patch applies exactly once.
rm -rf -- "$SRC"
tar -xzf "$tarball" -C "$WORK/src"
patch -d "$SRC" -p1 <"$HERE/sdl-rail-standalone-layered-popups.patch"

# Client-only build; libraries are installed next to the binary (RPATH), so it
# never mixes with the system libfreerdp3.
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_RPATH="$PREFIX/lib" \
  -DWITH_SERVER=OFF -DWITH_SHADOW=OFF -DWITH_PROXY=OFF -DWITH_SAMPLE=OFF \
  -DWITH_CLIENT_X11=OFF -DWITH_CLIENT_SDL2=OFF -DWITH_CLIENT_SDL3=ON \
  -DWITH_SDL_IMAGE_DIALOGS=OFF -DWITH_WAYLAND=OFF -DWITH_MANPAGES=OFF \
  -DWITH_FFMPEG=ON -DWITH_SWSCALE=ON -DWITH_DSP_FFMPEG=ON \
  -DWITH_PULSE=ON -DWITH_CUPS=OFF -DWITH_PCSC=OFF -DWITH_PKCS11=OFF \
  -DWITH_FUSE=OFF -DWITH_KRB5=ON -DWITH_AAD=OFF -DWITH_WEBVIEW=OFF \
  -DWITH_CJSON_REQUIRED=OFF -DWITH_JSON_DISABLED=ON -DWITH_URIPARSER=OFF \
  -DWITH_BINARY_VERSIONING=ON -DBUILD_TESTING=OFF
cmake --build "$BUILD"
rm -rf -- "$PREFIX"
cmake --install "$BUILD"
"$PREFIX/bin/sdl-freerdp3" --version
