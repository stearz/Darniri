import AppKit
import Carbon
import Foundation

@MainActor
final class OverviewInputHandler {
    enum KeyAction: Equatable {
        case clearSearchOrDismiss
        case activateSelection
        case navigate(Direction)
        case deleteBackward
        case appendToSearch(String)
        case consume
    }

    struct KeyHandlingResult: Equatable {
        let action: KeyAction
        let shouldConsume: Bool
    }

    private enum KeyCode {
        static let escape = UInt16(kVK_Escape)
        static let returnKey = UInt16(kVK_Return)
        static let keypadEnter = UInt16(kVK_ANSI_KeypadEnter)
        static let leftArrow = UInt16(kVK_LeftArrow)
        static let rightArrow = UInt16(kVK_RightArrow)
        static let downArrow = UInt16(kVK_DownArrow)
        static let upArrow = UInt16(kVK_UpArrow)
        static let tab = UInt16(kVK_Tab)
        static let delete = UInt16(kVK_Delete)
    }

    private weak var controller: OverviewController?

    var searchQuery: String = ""

    init(controller: OverviewController) {
        self.controller = controller
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let controller else { return false }
        guard controller.state.isOpen else { return false }

        let result = Self.keyHandlingResult(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            searchQuery: searchQuery
        )
        guard result.shouldConsume else { return false }

        switch result.action {
        case .clearSearchOrDismiss:
            if !searchQuery.isEmpty {
                searchQuery = ""
                controller.updateSearchQuery("")
            } else {
                controller.dismiss(reason: .cancel, animated: true)
            }
        case .activateSelection:
            controller.activateSelectedWindow()
        case let .navigate(direction):
            controller.navigateSelection(direction)
        case .deleteBackward:
            if !searchQuery.isEmpty {
                searchQuery = String(searchQuery.dropLast())
                controller.updateSearchQuery(searchQuery)
            }
        case let .appendToSearch(text):
            searchQuery += text
            controller.updateSearchQuery(searchQuery)
        case .consume:
            break
        }
        return true
    }

    // MARK: - Key handling result (pure, testable)

    static func keyHandlingResult(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String?,
        searchQuery _: String
    ) -> KeyHandlingResult {
        let relevantModifiers = modifierFlags.intersection([.shift, .command, .control, .option])

        switch keyCode {
        case KeyCode.escape:
            return .init(action: .clearSearchOrDismiss, shouldConsume: true)
        case KeyCode.returnKey,
             KeyCode.keypadEnter:
            guard relevantModifiers.isEmpty else { break }
            return .init(action: .activateSelection, shouldConsume: true)
        case KeyCode.leftArrow:
            guard relevantModifiers.isEmpty else { break }
            return .init(action: .navigate(.left), shouldConsume: true)
        case KeyCode.rightArrow:
            guard relevantModifiers.isEmpty else { break }
            return .init(action: .navigate(.right), shouldConsume: true)
        case KeyCode.downArrow:
            guard relevantModifiers.isEmpty else { break }
            return .init(action: .navigate(.down), shouldConsume: true)
        case KeyCode.upArrow:
            guard relevantModifiers.isEmpty else { break }
            return .init(action: .navigate(.up), shouldConsume: true)
        case KeyCode.tab:
            guard relevantModifiers.isEmpty || relevantModifiers == .shift else { break }
            let direction: Direction = relevantModifiers.contains(.shift) ? .left : .right
            return .init(action: .navigate(direction), shouldConsume: true)
        case KeyCode.delete:
            guard relevantModifiers.isEmpty else { break }
            return .init(action: .deleteBackward, shouldConsume: true)
        default:
            if relevantModifiers.intersection([.command, .control, .option]).isEmpty,
               let charactersIgnoringModifiers,
               let character = charactersIgnoringModifiers.first,
               charactersIgnoringModifiers.count == 1,
               (character.isLetter || character.isNumber || character == " ")
            {
                return .init(action: .appendToSearch(String(character)), shouldConsume: true)
            }
        }

        // Modified key events that don't match any plain navigation key are consumed
        // silently (not forwarded to the application). Layout commands (focus/move/workspace)
        // arrive as global Carbon hotkeys and are routed via CommandHandler.performCommand →
        // WMController.handleOverviewLayoutCommand, never through this NSEvent path.
        return .init(action: .consume, shouldConsume: true)
    }

    // MARK: - Live keymap resolution

    /// Resolves a raw key event (keyCode + NSEvent modifier flags) against the live
    /// hotkey bindings, returning the first matching `HotkeyCommand`.
    ///
    /// Hyper handling: when the hyperTrigger is a keyboard key (e.g. `.key(kVK_Option)`),
    /// the event tap suppresses the trigger key and sets `isActive`. NSEvent.modifierFlags
    /// therefore does NOT contain the trigger modifier when a hyper binding fires through
    /// the tap. However, in the overview the hot-key tap is still running — hyper events
    /// arrive via `HotkeyCenter.onCommand`, not as NSEvents. So when we see Option held in
    /// a raw NSEvent inside the overview, we treat it as a potential hyper trigger and try
    /// matching both as a regular (non-hyper) binding AND as a hyper binding (stripping the
    /// trigger modifier from the carbon modifiers and setting usesHyper=true).
    static func resolveLayoutCommand(
        keyCode: UInt32,
        modifierFlags: NSEvent.ModifierFlags,
        bindings: [HotkeyBinding],
        hyperTrigger: HyperKeyTrigger
    ) -> HotkeyCommand? {
        let carbonMods = carbonModifiers(from: modifierFlags)

        // Build the two candidates: a plain binding and (if applicable) a hyper binding.
        let plainCandidate = KeyBinding(keyCode: keyCode, modifiers: carbonMods, usesHyper: false)

        // For a key-based hyper trigger (e.g. Option), if the trigger modifier is present
        // in the raw event modifiers, also try matching as a hyper binding by stripping the
        // trigger modifier and setting usesHyper=true.
        let hyperCandidate: KeyBinding? = {
            let triggerMask = hyperTrigger.modifierMaskToExclude
            guard triggerMask != 0,
                  carbonMods & triggerMask != 0
            else { return nil }
            return KeyBinding(
                keyCode: keyCode,
                modifiers: carbonMods & ~triggerMask,
                usesHyper: true
            )
        }()

        // Only consider layout-relevant commands (focus, move, workspace navigation).
        for binding in bindings {
            guard let chordBinding = binding.binding.chordBinding,
                  !chordBinding.isUnassigned
            else { continue }
            guard isLayoutRelevantCommand(binding.command) else { continue }

            if chordBinding == plainCandidate { return binding.command }
            if let hyper = hyperCandidate, chordBinding == hyper { return binding.command }
        }
        return nil
    }

    /// Returns true for the commands that make sense to execute in the overview.
    /// Omits commands that manipulate real-window geometry (resize, fullscreen) or open
    /// other UI surfaces (command palette, scratchpad, overview itself).
    static func isLayoutRelevantCommand(_ command: HotkeyCommand) -> Bool {
        switch command {
        case .focus,
             .focusWindowOrWorkspaceUp,
             .focusWindowOrWorkspaceDown,
             .focusWindowDownOrTop, .focusWindowUpOrBottom,
             .focusWindowTop, .focusWindowBottom,
             .focusDownOrLeft, .focusUpOrRight,
             .focusPrevious,
             .focusColumnFirst, .focusColumnLast,
             .move,
             .moveWindowDown, .moveWindowUp,
             .moveWindowDownOrToWorkspaceDown,
             .moveWindowUpOrToWorkspaceUp,
             .moveColumn,
             .moveColumnToWorkspaceUp,
             .moveColumnToWorkspaceDown,
             .moveWindowToWorkspaceUp,
             .moveWindowToWorkspaceDown,
             .switchWorkspaceNext,
             .switchWorkspacePrevious:
            return true
        default:
            return false
        }
    }

    // MARK: - Carbon modifier conversion

    /// Converts NSEvent.ModifierFlags to Carbon modifier mask (same mapping used by
    /// HotkeyCenter.carbonModifiers(from:) for CGEventFlags, adapted for NSEvent).
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }

    func handleMouseMoved(at point: CGPoint, in layout: inout OverviewLayout) {
        let isCloseButton = layout.isCloseButtonAt(point: point)
        if let window = layout.windowAt(point: point) {
            layout.setHovered(handle: window.handle, closeButtonHovered: isCloseButton)
        } else {
            layout.setHovered(handle: nil)
        }
    }

    func handleMouseDown(at point: CGPoint, in layout: OverviewLayout) {
        guard let controller else { return }

        if layout.isCloseButtonAt(point: point) {
            if let window = layout.windowAt(point: point) {
                controller.closeWindow(window.handle)
            }
            return
        }

        if let window = layout.windowAt(point: point) {
            controller.selectAndActivateWindow(window.handle)
            return
        }

        controller.dismiss(reason: .cancel, animated: true)
    }

    func handleScroll(delta: CGFloat) {
        controller?.adjustScrollOffset(by: delta)
    }

    func reset() {
        searchQuery = ""
    }

    func matchingWindows(in layout: OverviewLayout) -> [OverviewWindowItem] {
        layout.allWindows.filter(\.matchesSearch)
    }

    func selectFirstMatch(in layout: inout OverviewLayout) {
        let matching = matchingWindows(in: layout)
        if let first = matching.first {
            layout.setSelected(handle: first.handle)
        } else {
            layout.setSelected(handle: nil)
        }
    }

    func autoSelectOnSearch(in layout: inout OverviewLayout) {
        guard !searchQuery.isEmpty else { return }

        let matching = matchingWindows(in: layout)

        if layout.selectedWindow() == nil || !(layout.selectedWindow()?.matchesSearch ?? false) {
            if let first = matching.first {
                layout.setSelected(handle: first.handle)
            }
        }
    }
}
