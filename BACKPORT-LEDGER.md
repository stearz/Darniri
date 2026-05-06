# Swift-Only Backport Ledger

Base: `6fde9b910a6dd531eeaf3892499729120ae75f49`
Source head: `ea732a35960ab2a899ecef393a37582d103d093e`
Source range: `6fde9b9..ea732a35960ab2a899ecef393a37582d103d093e`

This branch is a selective Swift-only backport. It must not import Zig source,
`COmniWMKernels`, Zig build plumbing, kernel ABI tests, or current-main kernel
adapter code.

## Prerequisites

- Create this work in an isolated worktree rooted at the base commit.
- Keep `Frameworks/GhosttyKit.xcframework/macos-arm64_x86_64/libghostty.a`
  available locally.
- `Scripts/ghostty-preflight.sh verify` must pass before `make build`,
  `make test`, or `make verify`.

## Buckets

- `direct-dry-run`: eligible for `merge-tree`/`cherry-pick --no-commit`, then audit.
- `swift-contextual`: Swift-only file list, but likely needs semantic review.
- `settings-final-state`: manual TOML/config port, not a JSON-then-TOML cherry-pick.
- `mixed-investigate-only`: only write a targeted Swift-native patch if the bug reproduces.
- `zig-build-skip`: Zig/kernel/build surface; skip.
- `merge-release-doc-skip`: merge, release, or nonessential docs/media churn.

## Record Template

```text
Commit:
Original subject:
Touched Swift files:
Touched Zig/build files:
Bug reproducible on 6fde9b9? yes/no/unknown
Tests added or updated:
Action: direct-dry-run / swift-contextual / settings-final-state / mixed-investigate-only / zig-build-skip / merge-release-doc-skip
Reason:
Backport commit:
```

## Records

Records are added as commits are accepted, skipped, or manually translated.

### `6b39ba9e95006860ec0b5b855bb46c90fc251872`

```text
Commit: 6b39ba9e95006860ec0b5b855bb46c90fc251872
Original subject: Fix cross-workspace hidden window reveals
Touched Swift files:
- Sources/OmniWM/Core/Controller/LayoutRefreshController.swift
- Tests/OmniWMTests/AXEventHandlerTests.swift
- Tests/OmniWMTests/LayoutRefreshControllerTests.swift
- Tests/OmniWMTests/RefreshRoutingTests.swift
Touched Zig/build files: none
Bug reproducible on 6fde9b9? unknown; source commit adds focused regression coverage for the reveal behavior
Tests added or updated:
- AXEventHandlerTests
- LayoutRefreshControllerTests
- RefreshRoutingTests
Action: direct-dry-run
Reason: Applies without manual edits, touches only Swift/test files, and passes the staged no-Zig audit.
Backport commit: this commit
```

### Settings Final-State Bundle Deferred

```text
Commit: 4167c898b1245b9eb26d6fa86282413e3188dfd0
Original subject: config: switch settings persistence to canonical JSON files
Touched Swift files:
- Sources/OmniWM/App/AppBootstrapPlanner.swift
- Sources/OmniWM/App/AppDelegate.swift
- Sources/OmniWM/App/UpdateCoordinator.swift
- Sources/OmniWM/Core/Config/*
- Sources/OmniWM/UI/SettingsView.swift
- Sources/OmniWM/UI/StatusBar/StatusBarMenu.swift
- Tests/OmniWMTests/*Settings*
Touched Zig/build files: none
Bug reproducible on 6fde9b9? no; this is a settings persistence migration, not a focused bugfix
Tests added or updated:
- SettingsStoreTests
- SettingsViewTests
- StatusBarMenuTests
- AppBootstrapPlannerTests
- AppDelegateIPCTests
- UpdateCoordinatorTests
Action: settings-final-state
Reason: Investigated as part of the TOML final-state bundle. Not landed in the conservative bugfix branch because the final TOML state depends on adjacent monitor rebinding, mouse-warp, quake geometry, and capability-profile changes outside a narrow config-file port.
Backport commit: not landed

Commit: 5fce6d9433cebfcb048b7e7915ffd03719ed35b9
Original subject: config: switch canonical settings persistence to TOML
Touched Swift files:
- Package.swift
- Sources/OmniWM/Core/Config/CanonicalTOMLConfig.swift
- Sources/OmniWM/Core/Config/SettingsFilePersistence.swift
- Sources/OmniWM/Core/Config/SettingsTOMLCodec.swift
- Tests/OmniWMTests/SettingsTOMLCodecTests.swift
- Tests/OmniWMTests/Fixtures/canonical-settings.toml
Touched Zig/build files:
- Package.swift keeps COmniWMKernels in the post-Zig OmniWM target dependency list
Bug reproducible on 6fde9b9? no; this is a settings persistence migration, not a focused bugfix
Tests added or updated:
- SettingsTOMLCodecTests
- SettingsStoreTests
- SettingsViewTests
Action: settings-final-state
Reason: Investigated with Zig/package linkage stripped locally. Not landed because it is not self-contained without broader post-Zig-era config support code.
Backport commit: not landed

Commit: 301c9a720464a74311505f023495dd985b2da090
Original subject: Fix settings.toml live reload for editor saves
Touched Swift files:
- Sources/OmniWM/Core/Config/SettingsFilePersistence.swift
- Sources/OmniWM/UI/SettingsView.swift
- Tests/OmniWMTests/SettingsStoreTests.swift
Touched Zig/build files: none
Bug reproducible on 6fde9b9? not applicable until the TOML settings migration exists
Tests added or updated:
- SettingsStoreTests
Action: settings-final-state
Reason: Deferred with the settings bundle. The bugfix is relevant only after adopting the final TOML persistence layer.
Backport commit: not landed
```

### Swift-Contextual Candidates Deferred

```text
Commit: 16ee0c44
Original subject: Stabilize border ownership reconciliation
Touched Swift files:
- Sources/OmniWM/Core/Border/*
- Sources/OmniWM/Core/Controller/BorderCoordinator.swift
- Sources/OmniWM/Core/Controller/AXEventHandler.swift
- Sources/OmniWM/Core/Controller/LayoutRefreshController.swift
- Sources/OmniWM/Core/Controller/NiriLayoutHandler.swift
- Sources/OmniWM/Core/Controller/ServiceLifecycleManager.swift
- Sources/OmniWM/Core/Controller/WMController.swift
- Sources/OmniWM/Core/Controller/WorkspaceNavigationHandler.swift
- Tests/OmniWMTests/Border*
Touched Zig/build files: none
Bug reproducible on 6fde9b9? unknown
Tests added or updated:
- BorderCoordinatorTests
- BorderManagerTests
- BorderWindowTests
Action: swift-contextual
Reason: Deferred. Dry-run shows multiple Swift conflicts across border/controller ownership paths, and no reproduced Swift-baseline bug justified importing a 2k-line reconciliation rewrite into the conservative branch.
Backport commit: not landed

Commit: a739e703
Original subject: Unify spring animations around exact snappy config
Touched Swift files:
- Sources/OmniWM/Core/Animation/SpringAnimation.swift
- Sources/OmniWM/Core/Controller/LayoutRefreshController.swift
- Sources/OmniWM/Core/Layout/Niri/*
- Sources/OmniWM/Core/Overview/OverviewAnimator.swift
- Tests/OmniWMTests/*Animation*
- Tests/OmniWMTests/LayoutRefreshControllerTests.swift
- Tests/OmniWMTests/NiriLayoutEngineTests.swift
Touched Zig/build files: none
Bug reproducible on 6fde9b9? unknown
Tests added or updated:
- SpringAnimationTests
- LayoutRefreshControllerTests
- NiriLayoutEngineTests
Action: swift-contextual
Reason: Deferred. Dry-run shows Swift conflicts in animation/layout paths, and this is a motion polish change rather than a confirmed Swift-baseline bugfix.
Backport commit: not landed

Commit: 7b19fdad
Original subject: Polish Dwindle motion with spring animations
Touched Swift files:
- Sources/OmniWM/Core/Animation/*
- Sources/OmniWM/Core/Controller/DwindleLayoutHandler.swift
- Sources/OmniWM/Core/Layout/Dwindle/*
- Tests/OmniWMTests/DwindleLayoutEngineTests.swift
- Tests/OmniWMTests/SpringAnimationTests.swift
Touched Zig/build files: none
Bug reproducible on 6fde9b9? unknown
Tests added or updated:
- DwindleLayoutEngineTests
- SpringAnimationTests
Action: swift-contextual
Reason: Deferred. Dry-run shows many Swift conflicts and one removed-local test surface; this is a broad Dwindle motion rewrite best handled as its own reproduced, targeted patch.
Backport commit: not landed
```

### `cbceeab7cd41d971c270dff87cfdc1cbf90a1577`

```text
Commit: cbceeab7cd41d971c270dff87cfdc1cbf90a1577
Original subject: Fix: include CGWindowList in pidsWithWindows to catch Electron windows SLS misses
Touched Swift files:
- Sources/OmniWM/Core/Ax/AXManager.swift
Touched Zig/build files: none
Bug reproducible on 6fde9b9? unknown; source commit fixes an SLS enumeration blind spot that can also affect the Swift-only AX discovery path
Tests added or updated:
- AXManagerTests
Action: direct-dry-run
Reason: Cherry-pick applies cleanly, touches only Swift AX discovery code, and passes the staged no-Zig audit. The explanatory comment was trimmed to ASCII while preserving the CGWindowList fallback rationale.
Backport commit: this commit
```

### `b18487723117ae927e720262c36ab962e38fe5ed`

```text
Commit: b18487723117ae927e720262c36ab962e38fe5ed
Original subject: Respect moved workspace for new app windows
Touched Swift files:
- Sources/OmniWM/Core/Ax/AXWindow.swift
- Sources/OmniWM/Core/Controller/AXEventHandler.swift
- Sources/OmniWM/Core/Controller/LayoutRefreshController.swift
- Sources/OmniWM/Core/Controller/WMController.swift
- Sources/OmniWM/Core/Rules/WindowRuleEngine.swift
- Sources/OmniWM/Core/Workspace/WorkspaceManager.swift
- Sources/OmniWM/IPC/IPCRuleRouter.swift
- Tests/OmniWMTests/AXEventHandlerTests.swift
- Tests/OmniWMTests/IPCRuleRouterTests.swift
Touched Zig/build files: none
Bug reproducible on 6fde9b9? unknown; source commit adds focused regression coverage for sibling window placement after manual workspace moves and explicit IPC rule apply behavior
Tests added or updated:
- AXEventHandlerTests
- IPCRuleRouterTests
Action: direct-dry-run
Reason: Cherry-pick required Swift-only conflict resolution and local test fixture adaptation. README and IPC docs were retained because they describe the same rule-application semantics now present in this Swift-only branch, and the staged patch passes the no-Zig audit.
Backport commit: this commit
```

### `cbe7cffbd682b10e1543ca915c013bdf1d7f6126`

```text
Commit: cbe7cffbd682b10e1543ca915c013bdf1d7f6126
Original subject: Fix status item visibility recovery
Touched Swift files:
- Sources/OmniWM/UI/HiddenBar/HiddenBarController.swift
- Sources/OmniWM/UI/StatusBar/StatusBarController.swift
- Sources/OmniWM/UI/StatusBar/StatusItemPersistence.swift
- Tests/OmniWMTests/MenuBarRecoveryTests.swift
Touched Zig/build files: none
Bug reproducible on 6fde9b9? unknown; source commit adds focused regression coverage for hidden/malformed AppKit status-item visibility restore state
Tests added or updated:
- MenuBarRecoveryTests
Action: direct-dry-run
Reason: Cherry-pick applies cleanly after the preceding status-item recovery backport. README documentation from the source commit was intentionally omitted because it references later settings/TOML behavior outside this bugfix bundle.
Backport commit: this commit
```

### `bc881a679346ff468aa280a0c904f13795548637`

```text
Commit: bc881a679346ff468aa280a0c904f13795548637
Original subject: Fix off-screen status item restore
Touched Swift files:
- Sources/OmniWM/UI/HiddenBar/HiddenBarController.swift
- Sources/OmniWM/UI/StatusBar/StatusBarController.swift
- Tests/OmniWMTests/MenuBarRecoveryTests.swift
Touched Zig/build files: none
Bug reproducible on 6fde9b9? unknown; source commit adds focused regression coverage for invalid menu bar autosave positions
Tests added or updated:
- MenuBarRecoveryTests
Action: direct-dry-run
Reason: Cherry-pick required a Swift-only conflict resolution around status bar helper placement, touches only Swift/test files, and passes the staged no-Zig audit.
Backport commit: this commit
```

### `74152463e4c4697043dcc663ee1a03fecb536543`

```text
Commit: 74152463e4c4697043dcc663ee1a03fecb536543
Original subject: Fix #234 trackpad gesture crash on Dwindle workspaces
Touched Swift files:
- Sources/OmniWM/Core/Controller/MouseEventHandler.swift
- Sources/OmniWM/Core/Layout/Niri/ViewportState+Gestures.swift
- Tests/OmniWMTests/MouseEventHandlerTests.swift
- Tests/OmniWMTests/ViewportGeometryTests.swift
Touched Zig/build files: none
Bug reproducible on 6fde9b9? unknown; source commit adds focused regression coverage for unsupported Dwindle gesture routing and invalid gesture geometry
Tests added or updated:
- MouseEventHandlerTests
- ViewportGeometryTests
Action: direct-dry-run
Reason: Cherry-pick required Swift-only conflict resolution. The port preserves the legacy snap helper already present on this branch, adds the invalid-geometry gesture guards, and narrows the geometry test file to only the two tests introduced by the source commit.
Backport commit: this commit
```

### `5475c44a32e899beacdd97d150af389dd7e2cbc1`

```text
Commit: 5475c44a32e899beacdd97d150af389dd7e2cbc1
Original subject: Fix quake terminal focus restoration
Touched Swift files:
- Sources/OmniWM/Core/Controller/WMController.swift
- Sources/OmniWM/QuakeTerminal/QuakeTerminalController.swift
- Tests/OmniWMTests/QuakeTerminalControllerTests.swift
- Tests/OmniWMTests/WMControllerFocusTests.swift
Touched Zig/build files: none
Bug reproducible on 6fde9b9? unknown; source commit adds focused regression coverage for Quake restore targets
Tests added or updated:
- QuakeTerminalControllerTests
- WMControllerFocusTests
Action: direct-dry-run
Reason: Cherry-pick applies without manual edits, touches only Swift/test files, and passes the staged no-Zig audit.
Backport commit: this commit
```

### `8a48b368e79c2366da692e6a2d2517f81dd39026`

```text
Commit: 8a48b368e79c2366da692e6a2d2517f81dd39026
Original subject: Fix Emacs full-rescan eviction
Touched Swift files:
- Sources/OmniWM/Core/Ax/AXWindow.swift
- Sources/OmniWM/Core/Ax/AppAXContext.swift
- Tests/OmniWMTests/AXWindowServiceTests.swift
- Tests/OmniWMTests/RefreshRoutingTests.swift
Touched Zig/build files: none
Bug reproducible on 6fde9b9? unknown; source commit adds focused regression coverage for top-level AX window admission
Tests added or updated:
- AXWindowServiceTests
- RefreshRoutingTests
Action: direct-dry-run
Reason: Cherry-pick applies without manual edits, touches only Swift/test files, and passes the staged no-Zig audit.
Backport commit: this commit
```

### `349247c73bf3f5b1cd84fab5cde8baa25fdb7651`

```text
Commit: 349247c73bf3f5b1cd84fab5cde8baa25fdb7651
Original subject: Apply global Niri settings without restart
Touched Swift files:
- Sources/OmniWM/Core/Controller/NiriLayoutHandler.swift
- Sources/OmniWM/Core/Controller/WMController.swift
- Tests/OmniWMTests/NiriLayoutEngineTests.swift
Touched Zig/build files: none
Bug reproducible on 6fde9b9? unknown; source commit adds focused regression coverage for live Niri settings updates
Tests added or updated:
- NiriLayoutEngineTests
Action: direct-dry-run
Reason: Cherry-pick applies without manual edits, touches only Swift/test files, and passes the staged no-Zig audit.
Backport commit: this commit
```

### `de13d4ccdb0aa683c79fe2fb4badec96bf362a80`

```text
Commit: de13d4ccdb0aa683c79fe2fb4badec96bf362a80
Original subject: Fix command hotkey capture on non-QWERTY keyboards
Touched Swift files:
- Sources/OmniWM/UI/KeyRecorderView.swift
- Tests/OmniWMTests/KeyRecorderViewTests.swift
Touched Zig/build files: none
Bug reproducible on 6fde9b9? unknown; source commit adds focused regression coverage for non-QWERTY capture
Tests added or updated:
- KeyRecorderViewTests
Action: direct-dry-run
Reason: Clean dry-run and cherry-pick, touches only Swift/test files, and passes the staged no-Zig audit.
Backport commit: this commit
```
