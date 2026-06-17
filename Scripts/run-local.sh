#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/dist/Darniri-dev.app"
BUILD_DIR="$ROOT_DIR/.build/debug"

cd "$ROOT_DIR"

echo "Building..."
swift build

echo "Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/Darniri"                    "$APP/Contents/MacOS/Darniri"
cp "$ROOT_DIR/Info.plist"                 "$APP/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns"     "$APP/Contents/Resources/AppIcon.icns"
cp -R "$BUILD_DIR/Darniri_Darniri.bundle"  "$APP/Contents/Resources/"

# Sign with a stable self-signed identity ("Darniri Dev") rather than ad-hoc (-).
# A stable identity gives an identity-based designated requirement, so macOS TCC
# (Accessibility / Input Monitoring) grants persist across rebuilds instead of being
# dropped every time the binary's cdhash changes. Falls back to ad-hoc if the cert
# is missing (e.g. CI / a fresh machine).
SIGN_IDENTITY="Darniri Dev"
if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
  echo "Signing with '$SIGN_IDENTITY'..."
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
else
  echo "Signing (ad-hoc; '$SIGN_IDENTITY' cert not found)..."
  codesign --force --deep --sign - "$APP"
fi

echo "Launching..."
pkill -x Darniri 2>/dev/null || true
sleep 0.5
open "$APP"

echo "Done. Look for the ⊙ icon in your menu bar."
echo "Grant Accessibility access in System Settings → Privacy & Security → Accessibility if prompted."
