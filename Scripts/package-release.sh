#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="$(swift build --configuration release --arch arm64 --show-bin-path)"
EXECUTABLE="$BUILD_DIR/Darniri"
# Info.plist is linker input rather than a Swift source. Always relink when
# packaging so a version-only change cannot reuse stale embedded metadata.
rm -f "$EXECUTABLE"
swift build --configuration release --arch arm64 --disable-sandbox --product Darniri

# Fail before publication if the archive would contain the wrong architecture.
test "$(lipo -archs "$EXECUTABLE")" = arm64
test -x "$EXECUTABLE"
mkdir -p dist
COPYFILE_DISABLE=1 tar -czf dist/Darniri-arm64.tar.gz -C "$BUILD_DIR" Darniri
test "$(tar -tzf dist/Darniri-arm64.tar.gz)" = Darniri
shasum -a 256 dist/Darniri-arm64.tar.gz

./Scripts/assemble-app.sh "$EXECUTABLE" "$ROOT_DIR/dist/Darniri.app"
codesign --force --sign - dist/Darniri.app
codesign --verify --strict dist/Darniri.app
rm -f dist/Darniri-arm64.zip
ditto -c -k --keepParent dist/Darniri.app dist/Darniri-arm64.zip
shasum -a 256 dist/Darniri-arm64.zip
python3 Scripts/verify-release.py
