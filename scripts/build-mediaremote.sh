#!/bin/bash
# Builds Vendor/mediaremote-adapter into MediaRemoteAdapter.framework with
# plain clang (no CMake), as a universal binary.
#
# The framework is not linked against: Gobbl runs
#   /usr/bin/perl mediaremote-adapter.pl <framework> stream
# because /usr/bin/perl is entitled to MediaRemote on macOS 15.4+ and our app
# is not. See Vendor/mediaremote-adapter (BSD-3, ungive/mediaremote-adapter).
#
# Usage: scripts/build-mediaremote.sh <output-dir>   (skips if up to date)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Vendor/mediaremote-adapter"
OUT="${1:-$ROOT/build/mediaremote}"
FW="$OUT/MediaRemoteAdapter.framework"
BIN="$FW/Versions/A/MediaRemoteAdapter"

sources=("$SRC"/src/adapter/*.m "$SRC"/src/private/MediaRemote.m "$SRC"/src/utility/*.m)

if [ -f "$BIN" ] && [ -z "$(find "$SRC" -newer "$BIN" -type f | head -1)" ]; then
  echo "MediaRemoteAdapter.framework up to date"
  exit 0
fi

rm -rf "$FW"
mkdir -p "$FW/Versions/A/Resources"
xcrun clang -dynamiclib -fobjc-arc -fvisibility=default -O2 \
  -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
  -I "$SRC/include" -I "$SRC/src" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  -o "$BIN" "${sources[@]}"

cat > "$FW/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
  <key>CFBundleIdentifier</key><string>com.xeve.gobbl.MediaRemoteAdapter</string>
  <key>CFBundleName</key><string>MediaRemoteAdapter</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.7.7</string>
  <key>CFBundleVersion</key><string>0.7.7</string>
</dict>
</plist>
PLIST

ln -sfn A "$FW/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter"
ln -sfn Versions/Current/Resources "$FW/Resources"
codesign --force --sign - "$FW" >/dev/null
echo "Built $FW"
