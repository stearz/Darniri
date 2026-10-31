# Releasing Darniri

Stable releases ship an ARM64 executable in `Darniri-arm64.tar.gz`, available through GitHub Releases and `stearz/tap/darniri` on Homebrew.

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

   The script builds an explicit ARM64 release executable, checks its architecture, and prints the archive checksum. The archive must contain only `Darniri`.

5. Open the release preparation pull request. The Checks workflow runs the same checks and verifies ARM64 release packaging. Merge after review and successful checks.

## Publish

Tag the merged release commit, matching the version in `Info.plist`:

```sh
git tag v<version> <merged-commit>
git push origin v<version>
```

The Release workflow reruns Checks before publishing. It validates the tag against `Info.plist`, requires the matching release notes, builds the archive, creates the GitHub release using those notes, and updates the Homebrew formula with the tag and SHA256.

The repository's `TAP_GITHUB_TOKEN` Actions secret must permit writes to `stearz/homebrew-tap`. If the tap update fails after the GitHub release is created, update the formula using that release's artifact and checksum before announcing availability through Homebrew.

Verify that the published release has the expected archive and notes and that the tap points to the new version and checksum. `Scripts/package-app.sh` remains a separate helper for local app bundles; the release workflow uses `Scripts/package-release.sh`.
