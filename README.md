# Darniri

Darniri is a Darwin/macOS implementation of a Niri-style scrolling-column window manager. It narrows the project around the Niri workflow on macOS.

Darniri is forked from [OmniWM](https://github.com/barutsrb/omniwm). The repository keeps OmniWM's project history and contributor attribution where applicable, while Darniri has diverged in scope toward Niri-like window management on macOS.

The fork exists to keep Darniri deliberately focused on that narrower scope, without adjacent features such as a CLI, quake terminal, or dwindle layout.

## Demo Video

TBD

## Contributors

<p align="center">
  Thank you to everyone who contributed to OmniWM and to Darniri. Your ideas and code are what Darniri builds upon.
</p>

## Requirements

- macOS 15+ (Sequoia)
- Apple Silicon (ARM64) for prebuilt releases
- Accessibility permissions (prompted on launch)
- Screen Recording permission for overview window thumbnails and drag ghost
- Input Monitoring permission for Hyper-key (Ctrl+Alt) column-to-row bindings
- Displays have separate spaces **OFF**

## Installation

### Homebrew

Install Darniri as a macOS application:

```sh
brew install --cask stearz/tap/darniri
```

Open **Darniri** from Applications, Spotlight, or the terminal:

```sh
Darniri
```

The cask installs `Darniri.app` in Applications. Its `Darniri` terminal command opens the app and returns immediately, so closing the terminal does not stop the window manager. To update, run `brew update` followed by `brew upgrade --cask stearz/tap/darniri`.

If you previously installed the executable formula, quit Darniri and switch to the app installation:

```sh
brew uninstall --formula stearz/tap/darniri
brew install --cask stearz/tap/darniri
```

Your TOML configuration and saved window state stay in their existing locations. Homebrew distribution uses the cask only. For standalone use, download the executable archive from GitHub Releases or build from source.

### GitHub Releases

Download `Darniri-arm64.zip` from [Releases](https://github.com/stearz/Darniri/releases), extract it, and move `Darniri.app` to `/Applications`. Open it from Applications or Spotlight.

The app archive is ad-hoc signed. Developer ID signing and Apple notarization remain available through `Scripts/package-app.sh` when signing credentials are configured.

For standalone use, download `Darniri-arm64.tar.gz` and extract it:

```sh
tar -xzf Darniri-arm64.tar.gz
./Darniri
```

The tar archive contains the ARM64 executable, which runs in the foreground. The app installation supports launch at login and runs independently of the terminal. Follow the permission setup in Quick Start.

## Documentation

The documentation hub lives in [`docs/index.md`](docs/index.md).

- [Documentation Home](docs/index.md)
- [Architecture Guide](docs/ARCHITECTURE.md)
- [Contribution Docs](docs/CONTRIBUTING.md)
- [Canonical Contributing Guide](CONTRIBUTING.md)

## Quick Start

1. Open Darniri from Applications or Spotlight, or run the cask's `Darniri` command
2. In System Settings > Desktop & Dock > Mission Control, turn **OFF** `Displays have separate Spaces`
3. Log out of macOS and log back in for that change to take effect unless you had it off already
4. Grant Accessibility permissions in System Settings > Privacy & Security > Accessibility
5. Grant Screen Recording in System Settings > Privacy & Security > Screen Recording (for overview thumbnails and drag ghost)
6. Windows will automatically tile in columns; rows are created dynamically as windows are added
7. Use `Ctrl+←/→` to focus columns and `Ctrl+↑/↓` to focus windows within a column (spilling to the row above/below at the edges)
8. Click the menu bar icon to access Settings

New configurations use zero inner and outer gaps, enabled window borders, and an enabled workspace bar on the left. The bar size is 32, workspace labels are hidden, and empty rows are hidden. Existing saved configuration values are preserved.

### Launch at Login

The installed app enables launch at login on its first start. Change this in **Settings > General > Launch at Login** or in macOS Login Items. If macOS requires approval, use **Open Login Items Settings** in Darniri. Disabling login startup is remembered and is not overridden on the next launch.

Login registration applies to `Darniri.app` installed in `/Applications` or your user's `Applications` folder. Standalone executables and temporary development bundles do not register automatically.


## User Guide

### Layout

Darniri uses the Niri scrolling columns layout: windows are arranged in vertical columns that scroll horizontally. Each column can have multiple stacked windows or be "tabbed" (multiple windows, one visible at a time). Best for wide monitors with many windows.

#### Dynamic Row Stack

Windows are organized into a vertical stack of rows per monitor. Each row is an independent scrolling column layout. Rows replace the old named-workspace model:

- There is always an empty buffer row above and below the content rows, so focus and spill never wrap around.
- Rows are created automatically as windows are moved in, and removed when they become empty (except for the buffers).
- Each row independently remembers its column widths and horizontal scroll position.
- Drag a tiled window’s edge to change its column width. Darniri also accepts a different width enforced by the app and moves neighboring columns to keep the layout aligned. Windows stacked in one column share its width.
- The active row is shown by the vertical Row Indicator Bar (see below).
- Native macOS fullscreen windows release their space in the tiled layout. On leaving fullscreen, they are inserted into the layout again without reserving their previous column position.

### Keyboard Shortcuts

Settings > Hotkeys configures the Darniri modifier and an Arrow or Vim (`h/j/k/l`) keymap. Edit individual bindings and the navigation modifier in the TOML configuration file. The default navigation modifier is **Control** (^). Darniri automatically disables the conflicting macOS Mission Control / Spaces symbolic hotkeys (Ctrl+Arrows) while it runs, then restores them when it quits. Setting `navigationModifier = "option"` uses **Option** (⌥) for navigation and requires no system hotkey management.

For the Ctrl+Alt column-to-row bindings, Option (⌥) acts as the Hyper trigger key. Input Monitoring permission is required for those bindings to fire.

The tables below list all the default hotkeys:

#### Row Navigation

| Action                                              | Default Shortcut       |
| --------------------------------------------------- | ---------------------- |
| Focus left / right column                           | `Ctrl + ← / →`         |
| Focus window up/down in column, spill to row above/below at edge | `Ctrl + ↑ / ↓` |
| Move window up/down in column, spill to row above/below at edge  | `Ctrl + Shift + ↑ / ↓` |
| Move column to row above / below                    | `Ctrl + Alt + ↑ / ↓`   |
| Switch to row (workspace) back and forth            | `Ctrl + Option + Tab`  |

#### Focus

| Action                         | Default Shortcut           |
| ------------------------------ | -------------------------- |
| Focus Left / Right             | `Ctrl + ← / →`             |
| Focus Up / Down (in-column spill) | `Ctrl + ↑ / ↓`          |
| Focus Previous Window          | `Option + Tab`             |
| Focus First Column             | `Option + Home`            |
| Focus Last Column              | `Option + End`             |
| Toggle Command Palette         | `Control + Option + Space` |
| Toggle Workspace Bar           | `Unassigned`               |
| Toggle Overview                | `Option + Shift + O`       |

#### Move Window

| Action                        | Default Shortcut              |
| ----------------------------- | ----------------------------- |
| Move Left / Right             | `Ctrl + Shift + ← / →`        |
| Move Up / Down (in-column, spill at edge) | `Ctrl + Shift + ↑ / ↓` |

#### Monitor

| Action                 | Default Shortcut            |
| ---------------------- | --------------------------- |
| Focus Next Monitor     | `Control + Command + Tab`   |
| Focus Previous Monitor | `Unassigned`                |
| Focus Last Monitor     | `` Control + Command + ` `` |

#### Layout

| Action                              | Default Shortcut     |
| ----------------------------------- | -------------------- |
| Toggle Fullscreen                   | `Option + Return`    |
| Toggle Native Fullscreen            | `Unassigned`         |
| Balance Sizes                       | `Option + Shift + B` |
| Raise All Floating Windows          | `Option + Shift + R` |
| Toggle Focused Window Floating      | `Unassigned`         |
| Assign Focused Window to Scratchpad | `Unassigned`         |
| Toggle Scratchpad Window            | `Unassigned`         |

#### Column

| Action                      | Default Shortcut                   |
| --------------------------- | ---------------------------------- |
| Move Column Left / Right    | `Ctrl + Alt + ← / →`               |
| Move Column to Row Above    | `Ctrl + Alt + ↑`                   |
| Move Column to Row Below    | `Ctrl + Alt + ↓`                   |
| Toggle Column Tabbed        | `Option + T`                       |
| Cycle Column Width Forward  | `Option + .`                       |
| Cycle Column Width Backward | `Option + ,`                       |
| Toggle Column Full Width    | `Option + Shift + F`               |

`Move Left / Right` expels the focused window out of multi-window columns or consumes a single-window column into the adjacent column. `Move Up / Down` reorders windows within the current column.

### Features

#### Dynamic Row Indicator Bar

A vertical indicator bar shows the row stack for the current monitor:

- Rows are listed vertically (top to bottom).
- The active row is highlighted.
- Each row displays app icons for the windows it contains.
- Empty buffer rows are shown faintly unless **Hide Empty Workspaces** is enabled; that option shows only occupied rows.
- Toggle the bar from the menu bar icon or with the `Toggle Workspace Bar` hotkey.
- Configure position, **Bar Size**, label visibility, and empty-row visibility in Settings. Bar Size controls the height for horizontal bars and the width for side bars.

#### Command Palette

Quickly search windows from one shared palette:
- Open it from the global shortcut shown in `Keyboard Shortcuts`
- Type to fuzzy-search by window title or app name
- `Up` / `Down` move the selection
- `Enter` activates the selected result
- `Shift + Enter` summons the selected window to the right when available
- `Escape` dismisses the palette

#### Overview Mode

See all windows at once with thumbnails (requires Screen Recording permission):
- Open it from the global shortcut shown in `Keyboard Shortcuts`
- All rows are shown, including empty buffer rows as drop targets
- **Drag a window** (left button) to move it to another row, column gap, or empty row
- Click a window to focus it
- Type to filter/search windows; `Backspace` deletes search text
- `Arrow Keys` navigate the selection; `Tab` / `Shift + Tab` move horizontally
- `Enter` activates the selected window
- `Escape` clears the search first, then dismisses the overview when the search is empty

### Tips

- **Rows** - Windows are organized automatically into rows. Move windows between rows with `Ctrl+Shift+↑/↓` (window) or `Ctrl+Alt+↑/↓` (whole column). There are no named workspaces to configure.
- **System Hotkey Conflicts** - When using the default Control modifier, Darniri automatically disables the macOS Mission Control / Spaces shortcuts for Ctrl+Arrows. They are restored when Darniri quits.
- **App Rules** - Edit `[[appRules]]` in the TOML configuration to exclude apps from tiling or assign them to workspace slots
- **Mouse** - `Option + drag` swaps tiled windows; `Option + Shift + drag` inserts windows to a column
- **Mouse Resize** - Hold `Option` and right-drag a tiled window to resize

## Configuration

Access settings by clicking Darniri's status bar icon and selecting **Settings**. App rules, workspace slots, and individual hotkey bindings are configured in the TOML file.

Darniri stores its editable config at `${XDG_CONFIG_HOME:-$HOME/.config}/darniri/settings.toml`; that file is the canonical settings source and is live-reloaded when saved from an editor.

- Open the TOML file in your preferred editor. Its generated header documents app rules and workspace slots. Changing settings in the app rewrites the file and removes custom comments outside that header.
- The persisted window restore catalog lives in `${XDG_STATE_HOME:-$HOME/.local/state}/darniri` and stays out of dotfile-oriented config storage.

## App Rules

Configure per-application behavior using `[[appRules]]` entries in `settings.toml`:

- **Float** (`layout = "float"`) - Force specific apps to float (e.g., calculators, preferences windows)
- **Assign to Workspace** (`assignToWorkspace = "3"`) - Open first matching app windows on a specific workspace; later windows follow the app's current workspace unless rules are explicitly applied
- **Minimum Size** (`minWidth` / `minHeight`) - Prevent the layout engine from sizing windows below a threshold

```toml
[[appRules]]
bundleId = "com.apple.calculator"
layout = "float"
```

## Building from Source

Requirements:
- SwiftPM with Swift 6.3.2+
- macOS 15.0+

To run locally without signing:

```sh
./Scripts/run-local.sh
```

For development checks and the automated Release Please workflow, see [Releasing](docs/RELEASING.md). New changes accumulate in a release PR; merging that PR publishes the next version and updates Homebrew after successful checks. See [CHANGELOG.md](CHANGELOG.md) for release history.

## Contributing

Issues and pull requests are welcome on [GitHub](https://github.com/stearz/Darniri).

Start with [CONTRIBUTING.md](CONTRIBUTING.md) for the actual project guidelines, expectations, and preferred direction.

For deeper technical context, the docs pages that back the documentation site are here:

- [Architecture Guide](docs/ARCHITECTURE.md)
- [Contribution Docs](docs/CONTRIBUTING.md)
