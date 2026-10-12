#!/bin/bash
# Builds "Tyon Control.app" into ./build using only the Xcode command-line tools.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Tyon Control"
OUT="build"
APP="$OUT/$APP_NAME.app"
mkdir -p "$OUT"
touch "$OUT/.metadata_never_index"   # keep Spotlight pointed at the /Applications copy only

echo "▸ compiling"
swiftc -O -swift-version 5 -parse-as-library \
  -target arm64-apple-macosx14.0 \
  -module-name TyonControl \
  Sources/*.swift \
  -o "$OUT/TyonControl" \
  -framework SwiftUI -framework AppKit -framework IOKit -framework UniformTypeIdentifiers

echo "▸ assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/TyonControl" "$APP/Contents/MacOS/TyonControl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi
for png in Resources/*.png; do [ -f "$png" ] && cp "$png" "$APP/Contents/Resources/"; done
printf 'APPL????' > "$APP/Contents/PkgInfo"

# A stable signing identity keeps macOS permission grants (Accessibility) valid across rebuilds;
# an ad-hoc signature changes every build. Uses the local "Tyon Control Signing" certificate if
# it has been imported into the login keychain, otherwise falls back to ad hoc.
SIGN_IDENTITY="${TYON_SIGN_IDENTITY:-Tyon Control Signing}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
  echo "▸ signing with \"$SIGN_IDENTITY\""
  codesign --force --timestamp=none --identifier com.ashavolian.tyoncontrol --sign "$SIGN_IDENTITY" "$APP" >/dev/null
else
  echo "▸ signing (ad hoc – permission grants will not survive rebuilds)"
  codesign --force --sign - "$APP" >/dev/null
fi

echo "✓ built $APP"

if [ "${1:-}" = "--install" ]; then
  DEST="/Applications/$APP_NAME.app"
  echo "▸ installing to $DEST"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  touch "$DEST"
  mdimport "$DEST" 2>/dev/null || true
  echo "✓ installed; Spotlight: \"Tyon Control\""
fi
