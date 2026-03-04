#!/usr/bin/env bash
# appimage/build.sh — Build a portable AppImage for reshade-linux.sh
#
# Usage:
#   bash appimage/build.sh
#
# Output:
#   reshade-linux-x86_64.AppImage  (architecture suffix matches the build host)
#
# Requirements (all standard on a desktop Linux):
#   curl          — downloads appimagetool if not already in appimage/tools/
#   ImageMagick   — generates the icon (magick or convert)
#
# Optional:
#   yad           — if present on the build host it will be bundled inside the
#                   AppImage, so GUI mode works on systems without yad installed.
#                   GTK3 / GLib / X11 are intentionally NOT bundled; they are
#                   universally available on desktop distros.
#
# The generated AppImage is self-contained (apart from GTK):
#   • Run it directly:         ./reshade-linux-x86_64.AppImage
#   • No installation needed.
#   • Works wherever bash ≥ 4.4 and GTK 3 are present.

set -euo pipefail

# ─── Paths ────────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPIMAGE_DIR="$REPO_ROOT/appimage"
TEMPLATE_DIR="$APPIMAGE_DIR/AppDir"       # versioned template (AppRun, .desktop)
BUILD_DIR="/tmp/reshade-linux-appdir"     # working copy, rebuilt each run
TOOLS_DIR="$APPIMAGE_DIR/tools"           # cached appimagetool (gitignored)
ICON_SIZE=256

# ─── Architecture ─────────────────────────────────────────────────────────────
_ARCH="$(uname -m)"
OUTPUT="$REPO_ROOT/reshade-linux-${_ARCH}.AppImage"

# ─── Helpers ──────────────────────────────────────────────────────────────────
_red='\033[31m'; _cyn='\033[36m'; _rst='\033[0m'
die()  { printf "${_red}ERROR:${_rst} %s\n" "$*" >&2; exit 1; }
step() { printf "${_cyn}>>>${_rst} %s\n" "$*"; }

# ─── Prerequisites ────────────────────────────────────────────────────────────
command -v curl &>/dev/null || die "curl is required"

if command -v magick &>/dev/null; then
    _CONVERT=(magick)
elif command -v convert &>/dev/null; then
    _CONVERT=(convert)
else
    die "ImageMagick not found — install it to generate the app icon"
fi

# ─── Fresh build directory ────────────────────────────────────────────────────
step "Preparing build directory"
rm -rf "$BUILD_DIR"
cp -a "$TEMPLATE_DIR" "$BUILD_DIR"
mkdir -p "$BUILD_DIR/usr/bin" "$BUILD_DIR/usr/lib"
chmod +x "$BUILD_DIR/AppRun"

# ─── Icon (generated via ImageMagick) ─────────────────────────────────────────
step "Generating icon"
"${_CONVERT[@]}" \
    -size "${ICON_SIZE}x${ICON_SIZE}" xc:'#181825' \
    -fill '#e94560' \
    -draw "circle $((ICON_SIZE / 2)),$((ICON_SIZE / 2)) $((ICON_SIZE / 2)),8" \
    -fill white -font 'DejaVu-Sans-Bold' -pointsize 80 \
    -gravity Center -annotate 0 'RS' \
    -fill '#a8dadc' -font 'DejaVu-Sans' -pointsize 22 \
    -gravity South -annotate +0+28 'Linux' \
    "$BUILD_DIR/reshade-linux.png"

# ─── Main script ──────────────────────────────────────────────────────────────
step "Copying reshade-linux.sh"
cp "$REPO_ROOT/reshade-linux.sh" "$BUILD_DIR/usr/bin/reshade-linux.sh"
chmod +x "$BUILD_DIR/usr/bin/reshade-linux.sh"

# ─── Bundle yad (optional) ────────────────────────────────────────────────────
# We copy yad itself and any non-system, non-GTK library dependencies so that
# GUI mode works on target systems even if yad is not installed there.
#
# Intentionally EXCLUDED (always present on desktop systems):
#   libgtk-3, libgdk-3, libglib-2, libgio-2, libgobject-2, libgmodule-2,
#   libpango-1, libcairo-2, libatk-1, libX*, libxcb*, libwayland*,
#   libdbus-1, libc, libm, libpthread, libdl, librt, libstdc++, libgcc_s

_EXCLUDE_RE='^lib(gtk-3|gdk_pixbuf-2|gdk-3|glib-2|gio-2|gobject-2|gmodule-2|gthread-2|pango-1|pangocairo-1|pangoft2-1|cairo|cairo-gobject-2|atk-1|X[a-zA-Z]|xcb|xkb|wayland|epoxy|dbus-1|ffi|z\.|lzma|selinux|c\.|m\.|pthread|dl\.|rt\.|stdc|gcc[_-]|resolv|nss|blkid|mount|uuid|util|pcre|gnutls|p11-kit|tasn1|nettle|hogweed|gmp|idn2|unistring|psl)'

_YAD="$(command -v yad 2>/dev/null || true)"
if [[ -n $_YAD ]]; then
    step "Bundling yad from $_YAD"
    cp "$_YAD" "$BUILD_DIR/usr/bin/yad"
    _bundled=0
    while IFS= read -r _lib; do
        _name="$(basename "$_lib")"
        if [[ "$_name" =~ $_EXCLUDE_RE ]]; then
            continue
        fi
        if [[ -f "$_lib" && ! -e "$BUILD_DIR/usr/lib/$_name" ]]; then
            cp "$_lib" "$BUILD_DIR/usr/lib/$_name"
            printf '  bundled: %s\n' "$_name"
            ((_bundled++)) || true
        fi
    done < <(ldd "$_YAD" 2>/dev/null | awk '/=> \// {print $3}')
    step "Bundled yad + $_bundled extra lib(s)"
else
    step "yad not found on build host — AppImage will use system yad if available"
fi

# Remove usr/lib if it ended up empty
[[ -z "$(ls -A "$BUILD_DIR/usr/lib" 2>/dev/null)" ]] && rmdir "$BUILD_DIR/usr/lib"

# ─── appimagetool ─────────────────────────────────────────────────────────────
mkdir -p "$TOOLS_DIR"
_TOOL="$TOOLS_DIR/appimagetool-${_ARCH}.AppImage"
if [[ ! -x "$_TOOL" ]]; then
    step "Downloading appimagetool"
    curl -L --progress-bar \
        "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${_ARCH}.AppImage" \
        -o "$_TOOL"
    chmod +x "$_TOOL"
fi

# ─── Build ────────────────────────────────────────────────────────────────────
step "Building $OUTPUT"
ARCH="$_ARCH" "$_TOOL" --appimage-extract-and-run "$BUILD_DIR" "$OUTPUT"

step "Done!"
printf '  %s\n' "$OUTPUT"
printf '  Run:  chmod +x %s && %s\n' \
    "$(basename "$OUTPUT")" "./$(basename "$OUTPUT")"
