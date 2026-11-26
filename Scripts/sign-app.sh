#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${DARNIRI_SIGNING_MODE:-developer-id}"
CHECK_ONLY=false
if [ "${1:-}" = --check ]; then
  CHECK_ONLY=true
  shift
fi

case "$MODE" in
  developer-id)
    # Select a usable identity (certificate AND private key). Never silently
    # change signing channels: that changes the app's privacy identity.
    IDENTITY="$(python3 - <<'PY'
import os, re, subprocess, sys
command = ["security", "find-identity", "-v", "-p", "codesigning"]
if os.environ.get("DARNIRI_SIGNING_KEYCHAIN"):
    command.append(os.environ["DARNIRI_SIGNING_KEYCHAIN"])
identities = re.findall(r'\b([A-Fa-f0-9]{40}) "(Developer ID Application: [^"\n]+)"',
                        subprocess.check_output(command, text=True))
requested = os.environ.get("DARNIRI_SIGNING_IDENTITY", "")
team = os.environ.get("DARNIRI_TEAM_ID", "")
identities = [(sha, name) for sha, name in identities
              if (not requested or requested in (sha, name))
              and (not team or name.endswith("(" + team + ")"))]
if len(identities) != 1:
    sys.exit("error: expected one usable Developer ID Application identity. Create/import it in Xcode; "
             "set DARNIRI_TEAM_ID or DARNIRI_SIGNING_IDENTITY if several exist. "
             "See docs/SIGNING.md. No ad-hoc fallback was used.")
print(identities[0][0])
PY
)"
    ;;
  adhoc)
    IDENTITY=-
    echo 'Ad-hoc signing explicitly selected: development/CI only; permissions do not survive rebuilds.' >&2
    ;;
  *) echo 'error: DARNIRI_SIGNING_MODE must be developer-id or adhoc' >&2; exit 1 ;;
esac

if [ "$CHECK_ONLY" = true ]; then exit 0; fi
TARGET="${1:?Pass the app bundle or standalone executable}"
ARGS=(--force --sign "$IDENTITY" --identifier io.github.stearz.darniri)
if [ "$MODE" = developer-id ]; then
  ARGS+=(--options runtime --timestamp --entitlements "$ROOT_DIR/Darniri.entitlements")
  if [ -n "${DARNIRI_SIGNING_KEYCHAIN:-}" ]; then
    ARGS+=(--keychain "$DARNIRI_SIGNING_KEYCHAIN")
  fi
fi
codesign "${ARGS[@]}" "$TARGET"
codesign --verify --strict "$TARGET"
if [ "$MODE" = developer-id ]; then
  REQUIREMENT='identifier "io.github.stearz.darniri" and anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
  if [ -n "${DARNIRI_TEAM_ID:-}" ]; then
    # A team identifier is interpolated into a code requirement, not shell code.
    if ! [[ "$DARNIRI_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
      echo 'error: invalid DARNIRI_TEAM_ID' >&2
      exit 1
    fi
    REQUIREMENT="$REQUIREMENT and certificate leaf[subject.OU] = \"$DARNIRI_TEAM_ID\""
  fi
  codesign --verify --strict --test-requirement "=$REQUIREMENT" "$TARGET"
fi
