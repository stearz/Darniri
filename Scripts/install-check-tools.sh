#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="$ROOT_DIR/.build/check-tools"
DOWNLOAD_DIR="$(mktemp -d)"
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT

# Read the same versions that make verify enforces.
SWIFTFORMAT_VERSION="$(awk '/^SWIFTFORMAT_VERSION = / { print $3 }' "$ROOT_DIR/Makefile")"
SWIFTLINT_VERSION="$(awk '/^SWIFTLINT_VERSION = / { print $3 }' "$ROOT_DIR/Makefile")"

mkdir -p "$DESTINATION"
gh release download "$SWIFTFORMAT_VERSION" --repo nicklockwood/SwiftFormat \
  --pattern swiftformat.zip --dir "$DOWNLOAD_DIR"
gh release download "$SWIFTLINT_VERSION" --repo realm/SwiftLint \
  --pattern portable_swiftlint.zip --dir "$DOWNLOAD_DIR"
unzip -oq "$DOWNLOAD_DIR/swiftformat.zip" swiftformat -d "$DESTINATION"
unzip -oq "$DOWNLOAD_DIR/portable_swiftlint.zip" swiftlint -d "$DESTINATION"
chmod +x "$DESTINATION/swiftformat" "$DESTINATION/swiftlint"

echo "Check tools installed in $DESTINATION"
echo 'Run: PATH="$PWD/.build/check-tools:$PATH" make verify'
