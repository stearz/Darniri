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

echo "Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP"

echo "Launching..."
pkill -x Darniri 2>/dev/null || true
sleep 0.5
open "$APP"

echo "Done. Look for the ⊙ icon in your menu bar."
echo "Grant Accessibility access in System Settings → Privacy & Security → Accessibility if prompted."
