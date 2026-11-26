#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
SIGN_AND_NOTARIZE="${2:-true}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(swift build --package-path "$ROOT_DIR" -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)"
EXECUTABLE="$BUILD_DIR/Darniri"
APP_DIR="$ROOT_DIR/dist/Darniri.app"

if [ "$SIGN_AND_NOTARIZE" = true ]; then
  "$ROOT_DIR/Scripts/sign-app.sh" --check
  : "${DARNIRI_NOTARIZE_PROFILE:?Set the notarization Keychain profile}"
else
  export DARNIRI_SIGNING_MODE=adhoc
fi

echo "Running release checks..."
make -C "$ROOT_DIR" release-check

echo "Building Darniri universal binary ($CONFIG)..."
swift build --package-path "$ROOT_DIR" -c "$CONFIG" --arch arm64 --arch x86_64

echo "Verifying universal binary..."
lipo -info "$EXECUTABLE"

echo "Packaging $APP_DIR"
"$ROOT_DIR/Scripts/assemble-app.sh" "$EXECUTABLE" "$APP_DIR"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
fi

"$ROOT_DIR/Scripts/sign-app.sh" "$APP_DIR"
if [ "$SIGN_AND_NOTARIZE" = true ]; then
  "$ROOT_DIR/Scripts/notarize-app.sh" "$APP_DIR"
  echo "Done! $APP_DIR is signed and notarized."
else
  echo "Done! $APP_DIR is ad-hoc signed for testing only."
fi
