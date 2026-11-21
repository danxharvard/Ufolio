#!/bin/bash
# Builds "Hush Browser.app" (Intel + Apple Silicon) and a drag-to-install DMG.
#
#   ./scripts/build-app.sh            → build/Hush Browser.app, HushBrowser-<version>.zip (for updates) and .dmg
#   ./scripts/build-app.sh --no-dmg   → just the app
#
# Works with Apple's Command Line Tools; Xcode is not required.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
APP_NAME="Hush Browser"
BUILD="build"
APP="$BUILD/$APP_NAME.app"
SDK="$(xcrun --show-sdk-path)"

echo "→ Building Hush Browser $VERSION"
mkdir -p "$BUILD"

for ARCH in x86_64 arm64; do
  echo "  compiling for $ARCH"
  swiftc -O -parse-as-library -sdk "$SDK" -target "$ARCH-apple-macos13.0" \
    Sources/*.swift -o "$BUILD/Hush-$ARCH"
done
lipo -create "$BUILD/Hush-x86_64" "$BUILD/Hush-arm64" -output "$BUILD/Hush"

if [ ! -f Resources/AppIcon.icns ]; then
  echo "  drawing app icon"
  swift scripts/make-icon.swift "$PWD" >/dev/null
  iconutil -c icns "$BUILD/AppIcon.iconset" -o Resources/AppIcon.icns
fi

echo "  assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$BUILD/Hush" "$APP/Contents/MacOS/Hush"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Free "ad-hoc" signature: needed for Apple Silicon Macs to open the app at all.
codesign --force --deep --sign - "$APP"
codesign --verify --deep "$APP"

# The zip is what installed copies download when they update themselves.
ZIP="$BUILD/HushBrowser-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "✓ $ZIP ($(du -h "$ZIP" | cut -f1))"

if [ "${1:-}" != "--no-dmg" ]; then
  echo "  making installer disk image"
  DMG="$BUILD/HushBrowser-$VERSION.dmg"
  STAGE="$BUILD/dmg"
  rm -rf "$STAGE" "$DMG"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
  rm -rf "$STAGE"
  echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
fi
echo "✓ $APP"
