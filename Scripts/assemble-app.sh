#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE="${1:?Pass the built Darniri executable}"
APP_DIR="${2:?Pass the destination app bundle}"
test -x "$EXECUTABLE"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/Darniri"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Homebrew links this launcher, rather than the long-running app executable.
cat > "$APP_DIR/Contents/Resources/darniri" <<'LAUNCHER'
#!/bin/sh
SCRIPT="$0"
while [ -L "$SCRIPT" ]; do
  TARGET="$(/usr/bin/readlink "$SCRIPT")"
  case "$TARGET" in
    /*) SCRIPT="$TARGET" ;;
    *) SCRIPT="$(/usr/bin/dirname "$SCRIPT")/$TARGET" ;;
  esac
done
APP_DIR="$(cd "$(/usr/bin/dirname "$SCRIPT")/../.." && pwd -P)"
exec /usr/bin/open "$APP_DIR" "$@"
LAUNCHER
chmod +x "$APP_DIR/Contents/Resources/darniri"
plutil -lint "$APP_DIR/Contents/Info.plist"
