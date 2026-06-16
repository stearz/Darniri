import CoreGraphics
import Foundation

// MARK: - Private SkyLight API declaration

// CGSSetSymbolicHotKeyEnabled is exported from the SkyLight framework (formerly in
// HIToolbox/CoreGraphics private headers).  Signature verified against open-source
// references (yabai, phoenix, etc.) and confirmed to link on macOS 12–26.
@_silgen_name("CGSSetSymbolicHotKeyEnabled")
private func CGSSetSymbolicHotKeyEnabled(_ hotKeyID: Int32, _ enabled: Bool) -> CGError

// MARK: - Protocol

/// Abstraction over the private SkyLight API so orchestration logic is unit-testable
/// with a fake.  The live implementation calls CGSSetSymbolicHotKeyEnabled.
protocol SymbolicHotkeyControlling: AnyObject {
    func setEnabled(_ id: Int32, _ enabled: Bool)
}

// MARK: - Live implementation

final class LiveSymbolicHotkeyController: SymbolicHotkeyControlling {
    func setEnabled(_ id: Int32, _ enabled: Bool) {
        let result = CGSSetSymbolicHotKeyEnabled(id, enabled)
        if result != .success {
            print("[SymbolicHotkeyController] ID \(id): setEnabled(\(enabled)) failed (CGError \(result.rawValue))")
        }
    }
}

// MARK: - Managed IDs

/// The symbolic hotkey IDs managed by Darniri.
///
/// These are the macOS Spaces/Mission Control shortcuts that conflict with
/// Ctrl+Arrow (and Ctrl+Shift+Arrow) navigation bindings:
///
/// | ID | Default assignment            |
/// |----|-------------------------------|
/// | 32 | Mission Control  (Ctrl+↑)     |
/// | 33 | App Exposé       (Ctrl+↓)     |
/// | 34 | Mission Control  (Ctrl+Shift+↑) |
/// | 35 | App Exposé       (Ctrl+Shift+↓) |
/// | 79 | Move left a Space  (Ctrl+←)   |
/// | 80 | Move left a Space  (Ctrl+Shift+←) |
/// | 81 | Move right a Space (Ctrl+→)   |
/// | 82 | Move right a Space (Ctrl+Shift+→) |
///
/// All IDs have `enabled = true` as their macOS default state, so restoring
/// means re-enabling them (see Phase 0 findings in `.plan/08-phase0-outcome.md`).
enum SymbolicHotkeyManagedIDs {
    static let all: [Int32] = [32, 33, 34, 35, 79, 80, 81, 82]
}

// MARK: - Modifier setting

/// The modifier key used for Darniri's focus/move hotkeys.
///
/// - `control`: Uses Control (^). Darniri automatically disables the conflicting
///   macOS Spaces symbolic hotkeys while it runs, then restores them on quit.
/// - `option`: Uses Option (⌥). macOS does not reserve Option+Arrow at the system
///   level, so no symbolic hotkey management is needed.  Note that Option+← and
///   Option+→ are intercepted by text fields for word-by-word cursor movement;
///   using this modifier will break that behavior while Darniri's hotkeys are active.
enum NavigationModifier: String, CaseIterable {
    case control
    case option
}

// MARK: - Controller

/// Manages the disable/restore lifecycle of the conflicting macOS symbolic hotkeys.
///
/// State machine:
/// - `controlModifier` (default): on `activate()`, disable all managed IDs so
///   `RegisterEventHotKey` can claim Ctrl+Arrow. On `deactivate()`, re-enable all
///   managed IDs (restore to macOS default state).
/// - `optionModifier`: no symbolic hotkey changes needed. `activate()` and
///   `deactivate()` are no-ops.
///
/// Crash safety: an `atexit` handler and SIGINT/SIGTERM signal handlers are
/// registered on first `activate()` call so a crash cannot leave the user's
/// Space shortcuts permanently disabled.
@MainActor
final class SymbolicHotkeyController {
    private let impl: SymbolicHotkeyControlling
    private(set) var modifier: NavigationModifier

    /// Whether `activate()` has been called (and `deactivate()` has not been called since).
    /// Tracks the caller's intent regardless of whether the current modifier requires API calls.
    private var isStarted = false

    /// Whether the managed symbolic hotkeys are currently disabled (i.e., we owe a restore).
    private var hotkeysAreDisabled = false

    init(
        modifier: NavigationModifier = .control,
        impl: SymbolicHotkeyControlling = LiveSymbolicHotkeyController()
    ) {
        self.modifier = modifier
        self.impl = impl
    }

    // MARK: - Lifecycle

    /// Call before `HotkeyCenter.start()`.  When modifier == .control, disables the
    /// conflicting symbolic hotkeys and installs crash-safety handlers.
    /// Idempotent — safe to call multiple times.
    func activate() {
        guard !isStarted else { return }
        isStarted = true
        if modifier == .control {
            disableManaged()
            installCrashSafetyHandlers()
        }
    }

    /// Call on quit or when the user switches modifier to .option.
    /// Re-enables all managed symbolic hotkeys (macOS default = enabled).
    /// Idempotent — safe to call multiple times.
    func deactivate() {
        guard isStarted else { return }
        isStarted = false
        if hotkeysAreDisabled {
            restoreManaged()
        }
    }

    // MARK: - Modifier change

    /// Update the navigation modifier.  If the modifier changes while started,
    /// deactivates the old state and activates the new one.
    func setModifier(_ newModifier: NavigationModifier) {
        guard newModifier != modifier else { return }
        let wasStarted = isStarted
        if wasStarted {
            // Fully stop the current modifier's effects.
            isStarted = false
            if hotkeysAreDisabled {
                restoreManaged()
            }
        }
        modifier = newModifier
        if wasStarted {
            isStarted = true
            if modifier == .control {
                disableManaged()
                installCrashSafetyHandlers()
            }
        }
    }

    // MARK: - Private helpers

    private func disableManaged() {
        hotkeysAreDisabled = true
        for id in SymbolicHotkeyManagedIDs.all {
            impl.setEnabled(id, false)
        }
    }

    private func restoreManaged() {
        hotkeysAreDisabled = false
        // Restore to macOS defaults: all managed IDs are enabled by default.
        // We do NOT use a runtime snapshot because CGSIsSymbolicHotKeyEnabled
        // was found unreliable during Phase 0 (reported everything disabled even
        // when the plist had some enabled).
        for id in SymbolicHotkeyManagedIDs.all {
            impl.setEnabled(id, true)
        }
    }

    // MARK: - Crash safety

    /// Install atexit and signal handlers so a hard crash still restores the
    /// managed symbolic hotkeys.  Idempotent — safe to call multiple times.
    private func installCrashSafetyHandlers() {
        SymbolicHotkeyCrashSafety.install()
    }
}

// MARK: - Crash safety (atexit + signals)

/// Nonisolated crash-safety net: if the process dies without calling
/// `SymbolicHotkeyController.deactivate()`, these handlers re-enable the
/// managed IDs so the user's Space shortcuts are not permanently disabled.
///
/// The live `CGSSetSymbolicHotKeyEnabled` function is called directly here
/// (not through the protocol) because signal/atexit handlers must be C-compatible
/// and cannot capture context or dispatch to `@MainActor`.
enum SymbolicHotkeyCrashSafety {
    nonisolated(unsafe) private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true

        // atexit: called on normal and `exit()` termination
        atexit(symbolicHotkeyAtexitHandler)

        // SIGINT (^C) and SIGTERM (kill / launchd stop)
        signal(SIGINT, symbolicHotkeySIGINTHandler)
        signal(SIGTERM, symbolicHotkeySIGTERMHandler)
    }

    /// Re-enables all managed IDs.  Safe to call from a signal handler or atexit.
    static func restoreNow() {
        for id in SymbolicHotkeyManagedIDs.all {
            _ = CGSSetSymbolicHotKeyEnabled(id, true)
        }
    }
}

// Top-level C-compatible atexit handler.
private func symbolicHotkeyAtexitHandler() {
    SymbolicHotkeyCrashSafety.restoreNow()
}

// Top-level C-compatible signal handlers (no captured context allowed).
private func symbolicHotkeySIGINTHandler(_ sig: Int32) {
    SymbolicHotkeyCrashSafety.restoreNow()
    signal(SIGINT, SIG_DFL)
    raise(SIGINT)
}

private func symbolicHotkeySIGTERMHandler(_ sig: Int32) {
    SymbolicHotkeyCrashSafety.restoreNow()
    signal(SIGTERM, SIG_DFL)
    raise(SIGTERM)
}
