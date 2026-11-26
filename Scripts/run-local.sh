#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/dist/Darniri-dev.app"

cd "$ROOT_DIR"

"$ROOT_DIR/Scripts/sign-app.sh" --check

echo "Building..."
swift build
BUILD_DIR="$(swift build --show-bin-path)"

echo "Assembling $APP..."
"$ROOT_DIR/Scripts/assemble-app.sh" "$BUILD_DIR/Darniri" "$APP"

"$ROOT_DIR/Scripts/sign-app.sh" "$APP"

echo "Launching..."
pkill -x Darniri 2>/dev/null || true
sleep 0.5
open "$APP"

echo "Done. Look for the Darniri window icon in your menu bar."
echo "Grant Accessibility access in System Settings → Privacy & Security → Accessibility if prompted."
