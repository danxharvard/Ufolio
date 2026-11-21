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
  swiftc -O -parse-as-library -sdk "$SDK" -target "$ARCH-apple-macos15.0" \
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
cp CHANGELOG.md "$APP/Contents/Resources/CHANGELOG.md"   # shown in What's New and Software Update
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
  DMG="$BUILD/HushBrowser-$VERSION.dmg"
  rm -f "$DMG"
  if python3 -c "import dmgbuild" 2>/dev/null; then
    # The styled installer: drag Hush onto Applications over a custom background.
    echo "  making installer window"
    ART="$BUILD/dmg-art"
    swift scripts/make-dmg-background.swift "$ART" >/dev/null
    tiffutil -cathidpicheck "$ART/background.png" "$ART/background@2x.png" -out "$ART/background.tiff" 2>/dev/null
    python3 -m dmgbuild -s scripts/dmg-settings.py \
      -D app="$APP" -D background="$ART/background.tiff" \
      "$APP_NAME" "$DMG" >/dev/null
  else
    # Plain fallback when dmgbuild isn't installed (pip3 install dmgbuild).
    echo "  making plain installer disk image (install dmgbuild for the styled one)"
    STAGE="$BUILD/dmg"
    rm -rf "$STAGE"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
    rm -rf "$STAGE"
  fi
  echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
fi
echo "✓ $APP"
