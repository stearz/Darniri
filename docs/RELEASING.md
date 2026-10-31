# Releasing Darniri

Darniri follows the same Release Please flow as [voidshell](https://github.com/stearz/voidshell/blob/main/.github/workflows/release-please.yml): merge changes into `main`, review the generated release PR, then merge that PR to publish. No manual version bump, tag push, or separate release-notes file is needed for normal releases.

## Normal workflow

1. Use Conventional Commit titles for squash merges: `fix:` produces a patch release, `feat:` a minor release, and `feat!:` or a `BREAKING CHANGE:` footer a major release. `ci:`, `docs:`, and `chore:` changes alone do not normally cause a release. Include user-visible configuration changes and removals in the PR description and conventional commit body.
2. Every push to `main` runs Release Please. It creates or updates one release PR containing `CHANGELOG.md`, `VERSION`, `.release-please-manifest.json`, and both version fields in `Info.plist`. The build identifier now uses the same three-component version as the app version.
3. Review the generated changelog and version and wait for Checks to pass. The release PR stays open while more changes accumulate. Merging ordinary feature/fix PRs does not publish anything.
4. Merge the release PR when ready to ship. Release Please creates the version tag and GitHub release. The published-release event automatically starts the Release workflow against that exact tag.
5. The Release workflow reruns Checks, validates version metadata and tap authentication, builds both ARM64 archives, attaches them to the existing GitHub release, and updates the Homebrew formula and cask. Its final step downloads and compares both published assets and verifies that the tap commit was pushed.

A release is complete when the **Release workflow succeeds**, including the final verification step. A merged release PR or an existing GitHub release alone does not establish that downloads and Homebrew are ready.

The initial automation commit requests `1.2.0` using a one-time `Release-As: 1.2.0` commit footer so the pending app installation and login-start improvements ship in a minor release. Later releases use the usual Conventional Commit rules. Bootstrap history starts at the published `v1.1.0` commit, preserving earlier release history.

## One-time GitHub setup

- Set the Darniri Actions secret `RELEASE_TOKEN` to a token with **Contents**, **Pull requests**, and **Issues** read/write access to `stearz/Darniri`. It creates release PRs, labels, tags, and GitHub releases. The same token used in voidshell can be reused if it is also authorized for Darniri.
- Use a PAT or GitHub App token rather than the built-in `GITHUB_TOKEN` for Release Please: events created by `GITHUB_TOKEN` do not start the follow-up Checks and Release workflows. The Release Please workflow fails explicitly if `RELEASE_TOKEN` is missing.
- Keep `TAP_GITHUB_TOKEN` with Contents read/write access to `stearz/homebrew-tap` for the formula/cask update. This is a separate repository permission from `RELEASE_TOKEN`.
- Repository rules must permit the release automation to create branches, PRs, labels, and tags. Release PRs follow the normal review and Checks policy.

After setting the secret, the Release Please workflow can be run manually to create the first release PR without another code change. `VERSION` and the manifest start at the latest published version, `1.1.0`; installing automation does not itself claim that pending fixes have shipped.

## Artifacts and installation

Stable releases provide:

- `Darniri-arm64.zip`: an ad-hoc signed `Darniri.app`, installed in Applications by `brew install --cask stearz/tap/darniri`. Its linked `Darniri` command opens the installed app and returns immediately.
- `Darniri-arm64.tar.gz`: the standalone executable used by the legacy Homebrew formula.

`Scripts/verify-release.py` checks the archives, ARM64 architecture, embedded and bundled metadata, app icon, launcher, and alignment of the version file and release manifest. Switching an existing formula installation to the cask is documented in the README. `Scripts/package-app.sh` supports Developer ID signing and notarization when credentials are configured.

## Local verification

```sh
./Scripts/install-check-tools.sh
PATH="$PWD/.build/check-tools:$PATH" make release-check
./Scripts/package-release.sh
```

Do not manually edit `VERSION` or push a release tag during the normal workflow. To choose a specific version, use Release Please's `Release-As:` commit footer and let it prepare the release PR. Historical notes under `docs/releases/` remain available; new release notes are generated in `CHANGELOG.md` and copied by Release Please into the GitHub release body.

## Recover publication

If publication fails after Release Please creates the release, fix the cause and rerun the failed job. If a workflow correction on `main` is needed, run the Release workflow manually with the existing automated release tag. It loads the publishing workflow from the selected branch while checking out and verifying the requested tag's source. It uploads assets to the existing release and preserves its generated notes. Repeating a matching Homebrew update succeeds without creating an empty commit. This recovery path applies to releases using the new version manifest and metadata, rather than historical tags predating the automation.

Do not move or recreate a published tag to repair publication. Check the Release workflow, both assets, and both Homebrew definitions before declaring the release complete. Do not replay an older release after a newer one has shipped, because the tap update would point Homebrew back to that older version.
