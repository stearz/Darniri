#!/usr/bin/env bash
set -euo pipefail

APP="${1:?Pass the signed app bundle}"
PROFILE="${DARNIRI_NOTARIZE_PROFILE:?Set DARNIRI_NOTARIZE_PROFILE to a notarytool Keychain profile}"
# Refuse accidental submissions of an ad-hoc build.
codesign --verify --strict --test-requirement \
  '=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$APP"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
ditto -c -k --keepParent "$APP" "$TEMP_DIR/Darniri.zip"
NOTARY_ARGS=(submit "$TEMP_DIR/Darniri.zip" --keychain-profile "$PROFILE" --wait)
if [ -n "${DARNIRI_SIGNING_KEYCHAIN:-}" ]; then
  NOTARY_ARGS+=(--keychain "$DARNIRI_SIGNING_KEYCHAIN")
fi
xcrun notarytool "${NOTARY_ARGS[@]}"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
