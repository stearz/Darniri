# Changelog

## [1.2.0](https://github.com/stearz/Darniri/compare/v1.1.0...v1.2.0) (2026-10-31)


### Bug Fixes

* install Darniri as a macOS app with login startup and focused defaults ([#5](https://github.com/stearz/Darniri/issues/5)) ([70e8f79](https://github.com/stearz/Darniri/commit/70e8f79cc149ca2d641e64582f45e55d66471617))
* remove unnecessary unsafe isolation from update identifiers ([#6](https://github.com/stearz/Darniri/issues/6)) ([8c47c97](https://github.com/stearz/Darniri/commit/8c47c97a9e7f7169b3689567a79d825c9f11825d))


### Continuous Integration

* automate releases with release-please ([8972df4](https://github.com/stearz/Darniri/commit/8972df4c7fb7699c613e7ba41f2d65b8ec78bc5a))

## [1.1.0](https://github.com/stearz/Darniri/compare/v1.0.0...v1.1.0) (2026-10-31)

Darniri 1.1.0 introduces dynamic rows, improves multi-monitor window management, and simplifies configuration around the scrolling-column workflow.

### Added and improved

- Dynamic rows provide independent horizontal window stacks on each monitor, with empty buffer rows above and below occupied rows.
- A vertical row indicator displays app icons and the active row. **Hide Empty Workspaces** shows only occupied rows, including hiding empty buffer rows.
- Improved overview layout, keyboard navigation, and dragging windows between rows and columns.
- Improved handling of disconnected and reconnected monitors, including row migration and restoration.
- Corrected column centering during navigation and the space reserved for the row indicator; fixed a hang and hide the bar for fullscreen apps.
- Native macOS fullscreen windows now release their tiled layout space. When fullscreen ends, the window is inserted again without preserving its previous column position.
- App bundles can offer a restart when an updated version has already been installed. This does not download updates.
- Standalone executables skip app-only update notifications so Homebrew and direct downloads can start without an application bundle.

### Changed and removed

- App rules and workspace configuration are now edited in `settings.toml`; their dedicated settings pages have been removed. App rules remain supported.
- Hotkey settings focus on the Darniri modifier and Arrow/Vim keymaps. Individual shortcut bindings are edited in TOML.
- Mouse-wheel column scrolling and trackpad gesture navigation have been removed. Keyboard navigation, mouse dragging, and mouse resizing remain available.
- The Keep Awake feature and the menu actions for revealing or editing the settings file have been removed.

### Installation and upgrade

Requires macOS 15 or newer. Prebuilt downloads support Apple Silicon (ARM64).

```sh
brew install stearz/tap/darniri
```

For existing Homebrew installations:

```sh
brew update
brew upgrade stearz/tap/darniri
```

Quit and restart Darniri after upgrading. Alternatively, download `Darniri-arm64.tar.gz`, extract it, and run `./Darniri`. The archive contains the executable.

The settings file remains at `${XDG_CONFIG_HOME:-$HOME/.config}/darniri/settings.toml`. Keep a backup before editing it. Configuration changes made in the app rewrite the file; custom comments outside the generated header are removed.

See the [README](https://github.com/stearz/Darniri#readme) for permissions, keyboard shortcuts, and configuration.

## [1.0.0](https://github.com/stearz/Darniri/releases/tag/v1.0.0) (2026-06-13)

Initial Darniri release, forked from OmniWM.
