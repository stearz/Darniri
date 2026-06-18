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
- Accessibility permissions (prompted on launch)
- Screen Recording permission for overview window thumbnails and drag ghost
- Input Monitoring permission for Hyper-key (Ctrl+Alt) column-to-row bindings
- Displays have separate spaces **OFF**

## Installation

### Homebrew

Darniri does not have a release artifact yet, so the Homebrew tap currently installs from source:

```sh
brew install stearz/tap/darniri --HEAD
```

After installing, start Darniri from the terminal:

```sh
Darniri
```

This installs the Swift executable. A cask for installing `Darniri.app` will be added once signed release archives are available.

### GitHub Releases

1. Download the latest `Darniri.zip` from [Releases](https://github.com/stearz/Darniri/releases)
2. Extract and move `Darniri.app` to `/Applications`
3. In System Settings > Desktop & Dock > Mission Control, turn **OFF** `Displays have separate Spaces`
4. Log out of macOS and log back in for that change to take effect unless you had it off already
5. Launch Darniri and grant Accessibility permissions when prompted
6. Grant Screen Recording from System Settings > Privacy & Security > Screen Recording (required for overview thumbnails and the window drag ghost)
7. For Ctrl+Alt column-to-row bindings, grant Input Monitoring from Settings > Hotkeys

## Documentation

The documentation hub lives in [`docs/index.md`](docs/index.md).

- [Documentation Home](docs/index.md)
- [Architecture Guide](docs/ARCHITECTURE.md)
- [Contribution Docs](docs/CONTRIBUTING.md)
- [Canonical Contributing Guide](CONTRIBUTING.md)

## Quick Start

1. Launch Darniri from your Applications folder
2. In System Settings > Desktop & Dock > Mission Control, turn **OFF** `Displays have separate Spaces`
3. Log out of macOS and log back in for that change to take effect unless you had it off already
4. Grant Accessibility permissions in System Settings > Privacy & Security > Accessibility
5. Grant Screen Recording in System Settings > Privacy & Security > Screen Recording (for overview thumbnails and drag ghost)
6. Windows will automatically tile in columns; rows are created dynamically as windows are added
7. Use `Ctrl+←/→` to focus columns and `Ctrl+↑/↓` to focus windows within a column (spilling to the row above/below at the edges)
8. Click the menu bar icon to access Settings


## User Guide

### Layout

Darniri uses the Niri scrolling columns layout: windows are arranged in vertical columns that scroll horizontally. Each column can have multiple stacked windows or be "tabbed" (multiple windows, one visible at a time). Best for wide monitors with many windows.

#### Dynamic Row Stack

Windows are organized into a vertical stack of rows per monitor. Each row is an independent scrolling column layout. Rows replace the old named-workspace model:

- There is always an empty buffer row above and below the content rows, so focus and spill never wrap around.
- Rows are created automatically as windows are moved in, and removed when they become empty (except for the buffers).
- Each row independently remembers its column widths and horizontal scroll position.
- The active row is shown by the vertical Row Indicator Bar (see below).

### Keyboard Shortcuts

All shortcuts are customizable in Settings > Hotkeys. The default navigation modifier is **Control** (^). Darniri automatically disables the conflicting macOS Mission Control / Spaces symbolic hotkeys (Ctrl+Arrows) while it runs, then restores them when it quits. You can switch to **Option** (⌥) as the modifier in Settings if you prefer, which requires no system hotkey management.

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
- Empty buffer rows are shown faintly.
- Toggle the bar from the menu bar icon or with the `Toggle Workspace Bar` hotkey.
- Configure position, height, and appearance in Settings.

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
- **App Rules** - Exclude problematic apps from tiling or assign them to specific workspaces
- **Mouse** - `Option + drag` swaps tiled windows; `Option + Shift + drag` inserts windows to a column
- **Mouse Resize** - Hold `Option` and right-drag a tiled window to resize
- **Scroll Gestures (Mouse)** - Hold `Option + Shift + Mouse Scroll Wheel` (default, configurable) and scroll through columns horizontally
- **Trackpad Gestures** - Use horizontal gestures with 2/3/4 fingers (configurable); direction can be inverted (local hardware validation is limited)

## Configuration

Access settings by clicking Darniri's status bar icon and selecting **Settings** or **App Rules**.
Mouse and gesture settings are available in Settings.

Darniri stores its editable config at `${XDG_CONFIG_HOME:-$HOME/.config}/darniri/settings.toml`; that file is the canonical settings source and is live-reloaded when saved from an editor.

- **Reveal Settings File** and **Edit Settings File** open the canonical TOML file and recreate it from the running settings if it was deleted.
- The persisted window restore catalog lives in `${XDG_STATE_HOME:-$HOME/.local/state}/darniri` and stays out of dotfile-oriented config storage.

## App Rules

Configure per-application behavior in Settings > App Rules:

- **Always Float** - Force specific apps to always float (e.g., calculators, preferences windows)
- **Assign to Workspace** - Open first matching app windows on a specific workspace; later windows follow the app's current workspace unless rules are explicitly applied
- **Minimum Size** - Prevent the layout engine from sizing windows below a threshold

## Building from Source

Requirements:
- SwiftPM with Swift 6.3.2+
- macOS 15.0+

To run locally without signing:

```sh
./Scripts/run-local.sh
```

## Contributing

Issues and pull requests are welcome on [GitHub](https://github.com/stearz/Darniri).

Start with [CONTRIBUTING.md](CONTRIBUTING.md) for the actual project guidelines, expectations, and preferred direction.

For deeper technical context, the docs pages that back the documentation site are here:

- [Architecture Guide](docs/ARCHITECTURE.md)
- [Contribution Docs](docs/CONTRIBUTING.md)
