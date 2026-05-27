#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Mongolian Matrix Screensaver.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
EXECUTABLE="$MACOS_DIR/matrix-mongolian"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR"

swiftc "$ROOT_DIR/Sources/MatrixMongolian/main.swift" \
  -framework AppKit \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -o "$EXECUTABLE"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>matrix-mongolian</string>
  <key>CFBundleIdentifier</key>
  <string>local.matrix.mongolian.screensaver</string>
  <key>CFBundleName</key>
  <string>Mongolian Matrix Screensaver</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

mkdir -p "$BUILD_DIR/bin"
cp "$EXECUTABLE" "$BUILD_DIR/bin/matrix-mongolian"

echo "Built:"
echo "  $APP_DIR"
echo "  $BUILD_DIR/bin/matrix-mongolian"
