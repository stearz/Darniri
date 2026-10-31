#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build --configuration release --arch arm64 --disable-sandbox --product Darniri
BUILD_DIR="$(swift build --configuration release --arch arm64 --show-bin-path)"
EXECUTABLE="$BUILD_DIR/Darniri"

# Fail before publication if the archive would contain the wrong architecture.
test "$(lipo -archs "$EXECUTABLE")" = arm64
test -x "$EXECUTABLE"
mkdir -p dist
COPYFILE_DISABLE=1 tar -czf dist/Darniri-arm64.tar.gz -C "$BUILD_DIR" Darniri
test "$(tar -tzf dist/Darniri-arm64.tar.gz)" = Darniri
shasum -a 256 dist/Darniri-arm64.tar.gz
