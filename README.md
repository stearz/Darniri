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
- Input Monitoring permission for custom Hyper key shortcuts
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
6. For custom Hyper key shortcuts, grant Input Monitoring from Settings > Hotkeys

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
5. Windows will automatically tile in columns
6. Use the default shortcuts in `Keyboard Shortcuts` to navigate between windows
7. Click the menu bar icon to access Settings


## User Guide

### Layout

Darniri uses the Niri scrolling columns layout: windows are arranged in vertical columns that scroll horizontally. Each column can have multiple stacked windows or be "tabbed" (multiple windows, one visible at a time). Best for wide monitors with many windows.

### Keyboard Shortcuts

All shortcuts are customizable in Settings > Hotkeys. Single-key chords and the `Hyper` modifier are configured there. `Hyper` defaults to Control + Option + Shift + Command, and you can choose another key or mouse button as the Darniri modifier. The tables below list all the default hotkeys:

#### Workspace

| Action                                        | Default Shortcut                        |
| --------------------------------------------- | --------------------------------------- |
| Switch to Workspace 1-9                       | `Hyper + 1-9`                           |
| Move Window to Workspace 1-9                  | `Option + Shift + 1-9`                  |
| Switch to Previous Workspace (Back and Forth) | `Control + Option + Tab`                |
| Switch to Next Workspace                      | `Unassigned`                            |
| Switch to Previous Workspace (Sequential)     | `Unassigned`                            |
| Move Window to Workspace Up                   | `Control + Option + Shift + Up Arrow`   |
| Move Window to Workspace Down                 | `Control + Option + Shift + Down Arrow` |
| Move Column to Workspace 1-9                  | `Unassigned`                            |
| Move Column to Workspace Up                   | `Control + Option + Shift + Page Up`    |
| Move Column to Workspace Down                 | `Control + Option + Shift + Page Down`  |

#### Focus

| Action                         | Default Shortcut           |
| ------------------------------ | -------------------------- |
| Focus Left / Right / Up / Down | `Option + Arrow Keys`      |
| Focus Previous Window          | `Option + Tab`             |
| Traverse Backward              | `Unassigned`               |
| Traverse Forward               | `Unassigned`               |
| Focus First Column             | `Option + Home`            |
| Focus Last Column              | `Option + End`             |
| Focus Column 1-9               | `Control + Option + 1-9`   |
| Toggle Command Palette         | `Control + Option + Space` |
| Toggle Workspace Bar           | `Unassigned`               |
| Toggle Overview                | `Option + Shift + O`       |

#### Move Window

| Action                        | Default Shortcut              |
| ----------------------------- | ----------------------------- |
| Move Left / Right / Up / Down | `Option + Shift + Arrow Keys` |

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

| Action                      | Default Shortcut                                |
| --------------------------- | ----------------------------------------------- |
| Move Column Left / Right    | `Control + Option + Shift + Left / Right Arrow` |
| Toggle Column Tabbed        | `Option + T`                                    |
| Cycle Column Width Forward  | `Option + .`                                    |
| Cycle Column Width Backward | `Option + ,`                                    |
| Toggle Column Full Width    | `Option + Shift + F`                            |

`Move Left / Right` expels the focused window out of multi-window columns or consumes a single-window column into the adjacent column. `Move Up / Down` keeps the current in-column reorder behavior.

### Features

#### Command Palette

Quickly search windows from one shared palette:
- Open it from the global shortcut shown in `Keyboard Shortcuts`
- Type to fuzzy-search by window title or app name
- `Up` / `Down` move the selection
- `Enter` activates the selected result
- `Shift + Enter` summons the selected window to the right when available
- `Escape` dismisses the palette

#### Overview Mode

See all windows at once with thumbnails:
- Open it from the global shortcut shown in `Keyboard Shortcuts`
- Click a window to focus it
- Type to filter/search windows; `Backspace` deletes search text
- Alt + Shift + Mouse Scroll to zoom in/out
- `Arrow Keys` navigate the selection; `Tab` / `Shift + Tab` move horizontally
- `Enter` activates the selected window
- `Escape` clears the search first, then dismisses the overview when the search is empty

#### Workspace Bar

A visual indicator showing your workspaces:
- Displays open apps per workspace
- Click to switch workspaces or jump to that app
- If dedupe option is on click the app icon to get a popup with list of all its windows to jump to
- Configure position, height, and appearance in Settings

### Tips

- **Workspaces** - Create named workspaces in Settings to organize by project or context (You can use emojis 🥳)
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

## Contributing

Issues and pull requests are welcome on [GitHub](https://github.com/stearz/Darniri).

Start with [CONTRIBUTING.md](CONTRIBUTING.md) for the actual project guidelines, expectations, and preferred direction.

For deeper technical context, the docs pages that back the documentation site are here:

- [Architecture Guide](docs/ARCHITECTURE.md)
- [Contribution Docs](docs/CONTRIBUTING.md)
