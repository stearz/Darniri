# Stable signing and privacy permissions

Darniri keeps the bundle identifier `io.github.stearz.darniri` and uses a **Developer ID Application** identity for both local app builds and public releases. macOS associates privacy permissions with the app's designated code requirement. An ad-hoc requirement uses a build-specific code hash; Developer ID requirements identify the app and Apple developer team across builds. See [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

The first migration from an ad-hoc build, another developer team, or another signing channel can require granting Accessibility and other permissions again. Signing cannot restore or preapprove those grants. Keep the installed app at `/Applications/Darniri.app`; avoid running development and installed copies simultaneously. Actual permission retention must be checked on macOS across an update.

## Create the identity once

1. Enroll in the paid Apple Developer Program, using the Account Holder account.
2. In Xcode → Settings → Accounts, add the account, select the team, and open Manage Certificates.
3. Create **Developer ID Application**. Apple Development, Apple Distribution, and Developer ID Installer are different certificate types and are not used here.
4. Verify the certificate/private-key pair is available: `security find-identity -v -p codesigning`.

If Xcode cannot create the certificate, use [Apple's Developer ID instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates). Create the CSR on this Mac, download the issued certificate, and import it into the login Keychain. Keep its private key in Keychain; do not commit it.

`Scripts/sign-app.sh --check` validates that exactly one suitable identity exists. If several exist, set `DARNIRI_TEAM_ID` to the ten-character team identifier, or set `DARNIRI_SIGNING_IDENTITY` to the exact certificate name or SHA-1 fingerprint. The helper verifies the resulting signature's bundle identifier, Apple Developer ID certificate type, and team when specified. Let codesign generate its normal designated requirement; do not pin a build hash or a leaf certificate fingerprint in that requirement.

## Local app builds

`Scripts/run-local.sh` builds, packages, signs with Developer ID, and launches `dist/Darniri-dev.app`. The signing check runs before building or stopping the running app. The same identifier and signing channel keep the designated requirement compatible with the release app. `DARNIRI_SIGNING_KEYCHAIN` optionally selects a non-default Keychain.

For an intentionally disposable build without Developer ID, use `DARNIRI_SIGNING_MODE=adhoc Scripts/run-local.sh`. Its permissions are not stable across builds. There is no automatic fallback to ad hoc or a self-signed development certificate.

## Local notarization

Create an app-specific password at your Apple Account and store notarization credentials using notarytool's secure interactive password prompt:

```sh
xcrun notarytool store-credentials darniri-release \
  --apple-id 'YOUR_APPLE_ID' --team-id 'YOUR_TEAM_ID'
```

The password belongs in Keychain, not the repository, a command copied into chat, or shell history. Set `DARNIRI_NOTARIZE_PROFILE=darniri-release` when packaging. `Scripts/package-release.sh` produces the ARM64 release archives; `Scripts/package-app.sh release true` produces a universal signed and notarized app. Both use the common signing/notarization helpers. Signed public packaging fails when signing or notarization is unavailable; it never silently publishes an ad-hoc artifact.

Notarization adopts the hardened runtime, submits the signed app to Apple, staples the ticket, and checks the ticket and Gatekeeper acceptance before packaging. Local development builds are signed but do not submit every build for notarization.

## GitHub Actions setup

Export **only the Developer ID Application identity, including its private key**, from Keychain Access → My Certificates as a password-protected `.p12`. Store the export and its password securely outside this repository. For assisted setup, `Scripts/export-signing-identity.swift` can export only the identity selected by its SHA-1 fingerprint; it reads the export password from a private file, writes a protected P12 outside the repository, and may prompt for Keychain access. It does not export unrelated identities. Configure these Actions secrets in `stearz/Darniri`:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64 of the password-protected `.p12` identity |
| `APPLE_CERTIFICATE_PASSWORD` | The export password |
| `APPLE_ID` | Apple Account used for notarization |
| `APPLE_TEAM_ID` | Team that issued the Developer ID certificate |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for notarization |

Use a private secret-entry interface or `gh secret set` with input from a file/stdin. Never paste values into issue bodies, PR descriptions, chat, or documentation. The app-specific password is separate from the P12 password and the Apple Account login password.

The Release workflow imports the identity into a disposable runner Keychain, permits codesign access, validates the expected team, and stores a notarization profile there. The temporary P12 is removed after import; the Keychain is removed after publication even on failure. Existing `RELEASE_TOKEN` and `TAP_GITHUB_TOKEN` remain responsible for release automation and Homebrew publication.

Checks on PRs explicitly set `DARNIRI_SIGNING_MODE=adhoc` and never access signing secrets. They exercise packaging but do not establish Developer ID validity, notarization success, or privacy-permission retention. `Scripts/test-signing.py` checks signature selection and refusal to fall back using command stubs without accessing Keychain or running the window manager.

## Verify an update

Compare the installed app and the next signed build:

```sh
codesign -d -r- /Applications/Darniri.app
codesign -d -r- dist/Darniri.app
codesign --verify --strict dist/Darniri.app
xcrun stapler validate dist/Darniri.app
spctl --assess --type execute --verbose=2 dist/Darniri.app
```

Their designated requirements should identify the same bundle and Developer ID team. After the one-time migration grant, replace the installed app with a subsequent signed build and check Accessibility, window control, and any enabled Screen Recording/Input Monitoring features without resetting TCC. An Apple-notarized signature does not itself grant any privacy permission.
