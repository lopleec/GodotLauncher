#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PRODUCT_NAME="GodotLauncher"
APP_NAME="Godot Launcher"
EXECUTABLE_NAME="GodotLauncher"
BUNDLE_ID="com.luccazh.GodotLauncher"
MIN_SYSTEM_VERSION="14.0"
MARKETING_VERSION="1.7"
BUILD_VERSION="8"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$PRODUCT_NAME"

rm -rf "$DIST_DIR/GodotLauncher.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
cp "$ROOT_DIR/Resources/VersionLogo.png" "$APP_RESOURCES/VersionLogo.png"
cp -R "$ROOT_DIR/Resources/en.lproj" "$APP_RESOURCES/"
cp -R "$ROOT_DIR/Resources/zh-Hans.lproj" "$APP_RESOURCES/"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>zh-Hans</string>
  </array>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

for attempt in 1 2 3 4; do
  /usr/bin/xattr -cr "$APP_BUNDLE"
  /usr/bin/xattr -d com.apple.FinderInfo "$APP_BUNDLE" >/dev/null 2>&1 || true
  /usr/bin/xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_BUNDLE" >/dev/null 2>&1 || true
  if codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1; then
    /usr/bin/xattr -d com.apple.FinderInfo "$APP_BUNDLE" >/dev/null 2>&1 || true
    /usr/bin/xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_BUNDLE" >/dev/null 2>&1 || true
  fi
  if codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1; then
    break
  fi
  if [[ "$attempt" -eq 4 ]]; then
    echo "Unable to sign $APP_BUNDLE after clearing Finder metadata." >&2
    exit 1
  fi
  sleep 0.1
done

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$EXECUTABLE_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
