---
type: Procedure
title: "Darniri operating model"
description: "Development checks, documentation ownership, and runtime verification."
tags: ["development", "validation", "permissions"]
status: draft
generated: { by: codex, at: "2026-10-17T09:20:35+00:00" }
sources:
  - id: source-1
    resource: "../../README.md"
    title: "Build and permission setup"
  - id: source-2
    resource: "../../CONTRIBUTING.md"
    title: "Contribution policy"
  - id: source-3
    resource: "../../Makefile"
    title: "Development checks"
---

# Development

Use the [README](../../README.md) for supported macOS and Swift requirements and `Scripts/run-local.sh` for local running. Follow the root [contribution guide](../../CONTRIBUTING.md) for scope and review expectations.

The [Makefile](../../Makefile) defines `make verify` and `make release-check` as formatting checks, linting, a build, and the full Swift test suite; formatter and linter versions are pinned there. `Scripts/install-check-tools.sh` installs those versions locally. A successful build does not establish working focus, permissions, or window behavior.

The [release procedure](../RELEASING.md) owns versioning, release notes, and publication. Pull requests and tag releases run the Checks workflow, including ARM64 release packaging. Tagged releases publish the executable archive and update the Homebrew formula only after Checks passes.

# Verification boundaries

Changes to accessibility, focus, displays, input, and private framework integration require relevant macOS runtime checks. Repository documentation describes intended behavior and does not prove the current state of a running application.

# Knowledge maintenance

Keep this bundle small. Update its concepts when domain language, architectural boundaries, or operating procedures materially change. Detailed user and contributor documentation remains in the existing canonical documents; keep new concepts as draft until reviewed.

# Related project knowledge

- [Project overview](overview.md)
- [Architecture](architecture.md)
