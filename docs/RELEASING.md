# Releasing Darniri

Stable releases ship `Darniri-arm64.zip` containing `Darniri.app` for the Homebrew cask and `Darniri-arm64.tar.gz` for the standalone executable formula. Both are available through GitHub Releases. The cask installs the app in Applications and links a launcher that opens it without retaining the terminal process.

## Prepare a release

1. Update `CFBundleShortVersionString` in `Info.plist` and increment `CFBundleVersion`.
2. Write English release notes in `docs/releases/<version>.md`, including removed features and changes to configuration or installation. Update the README to describe the shipped behavior.
3. Install the formatter and linter versions pinned in the Makefile:

   ```sh
   ./Scripts/install-check-tools.sh
   PATH="$PWD/.build/check-tools:$PATH" make release-check
   ```

   The installer requires GitHub CLI (`gh`). `make release-check` runs formatting, lint, a debug build, and the full test suite.

4. Build the distribution archive on macOS:

   ```sh
   ./Scripts/package-release.sh
   tar -tzf dist/Darniri-arm64.tar.gz
   ```

   The script builds an explicit ARM64 release executable and assembles an ad-hoc signed app bundle. `Scripts/verify-release.py` checks both archives, ARM64 architecture, embedded and bundled version metadata, the app icon, and the terminal launcher. The tar archive must contain only `Darniri`. The script prints both archive checksums.

5. Open the release preparation pull request. The Checks workflow runs the same checks and verifies ARM64 release packaging. Merge after review and successful checks.

## Publish

Tag the merged release commit, matching the version in `Info.plist`:

```sh
git tag v<version> <merged-commit>
git push origin v<version>
```

The Release workflow reruns Checks before publishing. It validates the tag against `Info.plist`, requires the matching release notes, builds both archives, creates the GitHub release using those notes, and updates the Homebrew formula and cask with the tag and their respective SHA256 checksums. Repeating the tap update succeeds if both definitions already match.

The repository's `TAP_GITHUB_TOKEN` Actions secret must permit writes to `stearz/homebrew-tap`. If the tap update fails after the GitHub release is created, update the formula using that release's artifact and checksum before announcing availability through Homebrew.

Verify that the published release has both archives and the expected notes and that the formula and cask point to the new version and their respective checksums. `Scripts/package-app.sh` supports Developer ID signing and notarization when credentials are configured; the release workflow uses `Scripts/package-release.sh` with ad-hoc signing.
