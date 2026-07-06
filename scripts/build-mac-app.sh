#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DeskIt"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/$APP_NAME.iconset"

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/macos/Info.plist" "$CONTENTS_DIR/Info.plist"

swift "$ROOT_DIR/scripts/sync-apps.swift" "$ROOT_DIR" "$ROOT_DIR/config/apps.json" "$RESOURCES_DIR"
swift "$ROOT_DIR/scripts/render-app-icon.swift" "$ROOT_DIR/assets/app-icon-source.png" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/$APP_NAME.icns"

swiftc \
  "$ROOT_DIR/macos/DeskItApp.swift" \
  "$ROOT_DIR/macos/WebModuleView.swift" \
  "$ROOT_DIR/macos/NativeModules.swift" \
  -o "$MACOS_DIR/$APP_NAME" \
  -framework AppKit \
  -framework SwiftUI \
  -framework WebKit \
  -framework UniformTypeIdentifiers

chmod +x "$MACOS_DIR/$APP_NAME"

echo "Built $APP_DIR"
