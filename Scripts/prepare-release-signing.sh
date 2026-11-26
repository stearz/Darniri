#!/usr/bin/env bash
# GitHub Actions only: import the release identity into a disposable Keychain.
set -euo pipefail
umask 077
: "${RUNNER_TEMP:?Run this script on the GitHub Actions runner}"
: "${GITHUB_ENV:?GitHub Actions environment file is required}"
for NAME in APPLE_CERTIFICATE_P12_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD; do
  if [ -z "${!NAME:-}" ]; then
    echo "error: missing Actions secret $NAME; see docs/SIGNING.md" >&2
    exit 1
  fi
done

KEYCHAIN="$RUNNER_TEMP/darniri-signing.keychain-db"
CERTIFICATE="$RUNNER_TEMP/darniri-signing.p12"
KEYCHAIN_PASSWORD="$(uuidgen)$(uuidgen)"
SUCCESS=false
cleanup() {
  rm -f "$CERTIFICATE"
  if [ "$SUCCESS" != true ]; then
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
python3 - "$CERTIFICATE" <<'PY'
import base64, os, pathlib, sys
pathlib.Path(sys.argv[1]).write_bytes(base64.b64decode(os.environ["APPLE_CERTIFICATE_P12_BASE64"], validate=True))
PY
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$CERTIFICATE" -k "$KEYCHAIN" -P "$APPLE_CERTIFICATE_PASSWORD" \
  -f pkcs12 -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
export DARNIRI_SIGNING_KEYCHAIN="$KEYCHAIN"
export DARNIRI_TEAM_ID="$APPLE_TEAM_ID"
export DARNIRI_SIGNING_MODE=developer-id
./Scripts/sign-app.sh --check
xcrun notarytool store-credentials darniri-release --keychain "$KEYCHAIN" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD"
{
  echo "DARNIRI_SIGNING_KEYCHAIN=$KEYCHAIN"
  echo "DARNIRI_TEAM_ID=$APPLE_TEAM_ID"
  echo 'DARNIRI_SIGNING_MODE=developer-id'
  echo 'DARNIRI_NOTARIZE_PROFILE=darniri-release'
} >> "$GITHUB_ENV"
SUCCESS=true
