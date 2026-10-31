---
type: Project
title: "Darniri overview"
description: "Purpose, layout vocabulary, and canonical documentation."
tags: ["macos", "window-manager", "niri"]
status: draft
generated: { by: codex, at: "2026-10-17T09:20:35+00:00" }
sources:
  - id: source-1
    resource: "../../README.md"
    title: "Darniri README"
  - id: source-2
    resource: "../../CONTRIBUTING.md"
    title: "Contribution guide"
---

# Purpose

Darniri is a macOS window manager focused on Niri-style scrolling columns. It derives from OmniWM and preserves upstream history and attribution. The project deliberately narrows its scope around this workflow; a CLI, quake terminal, and dwindle layout are outside the scope described by the [README](../../README.md).

# Domain language

- A column contains vertically stacked or tabbed windows and belongs to a horizontally scrolling layout.
- Dynamic rows form a vertical stack per monitor, with empty buffer rows above and below content. Each row retains its column widths and scroll position.
- The code still uses workspace terminology in several types. Consult the current implementation before interpreting workspace names as a separate user-facing model.
- The command palette finds and activates windows; overview exposes windows and rows for navigation and rearrangement.

# Canonical ownership

The [README](../../README.md) owns setup and user behavior; the [architecture guide](../ARCHITECTURE.md) owns technical explanations; the root [contribution guide](../../CONTRIBUTING.md) owns contribution policy. This bundle maps those sources without replacing them.

# Related project knowledge

- [Architecture](architecture.md)
- [Operating model](operating-model.md)
