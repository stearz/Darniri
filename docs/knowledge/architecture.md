---
type: Architecture
title: "Darniri architecture"
description: "Entry points for runtime coordination, layout, accessibility, and persistence."
tags: ["swift", "accessibility", "runtime"]
status: draft
generated: { by: codex, at: "2026-10-17T09:20:35+00:00" }
sources:
  - id: source-1
    resource: "../../Package.swift"
    title: "Swift package manifest"
  - id: source-2
    resource: "../ARCHITECTURE.md"
    title: "Architecture guide"
  - id: source-3
    resource: "../../Sources/Darniri/Core/Reconcile/RuntimeStore.swift"
    title: "Runtime store"
---

# Structure

[Package.swift](../../Package.swift) separates the `Darniri` library, the `DarniriApp` executable, and `DarniriTests`. Swift 6, AppKit, accessibility APIs, the private SkyLight framework, and TOML configuration support the application.

# Runtime boundaries

The [architecture guide](../ARCHITECTURE.md) maps application bootstrap, window discovery, rules, focus, event handling, refresh scheduling, the Niri layout engine, and accessibility frame application. Start there, then inspect the relevant implementation under `Sources/Darniri/Core/`.

Window identity distinguishes `WindowToken`, reference-oriented `WindowHandle`, and the accessibility bridge `AXWindowRef`. Preserve those distinctions when changing window lifecycle behavior.

Runtime coordination also has explicit reconciliation types under `Core/Reconcile/`, including [RuntimeStore](../../Sources/Darniri/Core/Reconcile/RuntimeStore.swift), `StateReducer`, and `Planner`. Treat the guide as an architectural map and inspect current code for exact behavior rather than assuming every diagram describes every path.

# Persistence and permissions

The [README](../../README.md) documents the canonical editable TOML settings file under the XDG config location and a separate restore catalog under the XDG state location. Settings and persisted restore state have different responsibilities.

Accessibility controls window management; Screen Recording supports thumbnails and drag ghosts; Input Monitoring supports the documented Hyper-key bindings. Private macOS APIs and OS permissions are integration boundaries requiring actual macOS checks when affected.

Native macOS fullscreen suspends a window's participation in the tiled layout and clears its saved Niri placement. Returning windows are inserted again rather than holding a placeholder or reserving their former column position.

Version metadata comes from the root `Info.plist`, embedded in the SwiftPM executable and copied into assembled app bundles. Update notifications and restart detection are enabled only for versioned app bundles. Standalone executables skip the app-only notification center.

`LoginItemManager` uses `SMAppService.mainApp` for startup registration of the installed stable app. macOS registration status is authoritative; UserDefaults records only whether the initial default has been applied. A default registration is requested once on first launch from Applications, and later user opt-outs are preserved. Login registration is machine-local and is not part of the portable TOML configuration. Development bundles and standalone executables do not register automatically.

# Related project knowledge

- [Project overview](overview.md)
- [Operating model](operating-model.md)
