import Carbon

enum HotkeyVisibility: String {
    case normal
    case advanced
    case hidden
}

struct ActionSpec: Equatable {
    let id: String
    let command: HotkeyCommand
    let title: String
    let keywords: [String]
    let category: HotkeyCategory
    let visibility: HotkeyVisibility
    let layoutCompatibility: LayoutCompatibility
    let defaultBinding: KeyBinding

    var searchTerms: [String] {
        ActionCatalog.uniqueTerms(
            [title, id, layoutCompatibility.rawValue]
                + keywords
        )
    }
}

enum ActionCatalog {
    private static let digitCodes: [UInt32] = [
        UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
        UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
        UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9)
    ]

    private static let specs: [ActionSpec] = buildSpecs()
    private static let specsByID = Dictionary(
        uniqueKeysWithValues: specs.map { ($0.id, $0) }
    )

    static func allSpecs() -> [ActionSpec] {
        specs
    }

    static func spec(for id: String) -> ActionSpec? {
        specsByID[id]
    }

    static func spec(for command: HotkeyCommand) -> ActionSpec? {
        specs.first { $0.command == command }
    }

    static func title(for command: HotkeyCommand) -> String? {
        spec(for: command)?.title
    }

    static func layoutCompatibility(for command: HotkeyCommand) -> LayoutCompatibility? {
        spec(for: command)?.layoutCompatibility
    }

    static func category(for id: String) -> HotkeyCategory? {
        spec(for: id)?.category
    }

    static func visibility(for id: String) -> HotkeyVisibility? {
        spec(for: id)?.visibility
    }

    // MARK: - Navigation-modifier-aware default bindings

    /// The action IDs whose default bindings change with NavigationModifier.
    /// Any ID in this set gets its binding replaced by navigationBindings(for:).
    static let navigationActionIDs: Set<String> = [
        "focus.left", "focus.right",
        "focusWindowOrWorkspaceUp", "focusWindowOrWorkspaceDown",
        "move.left", "move.right",
        "moveWindowUpOrToWorkspaceUp", "moveWindowDownOrToWorkspaceDown",
        "moveColumn.left", "moveColumn.right",
        "moveColumnToWorkspaceUp", "moveColumnToWorkspaceDown"
    ]

    /// Returns the raw (pre-defaultBinding-transform) KeyBinding for each navigation
    /// action under the given modifier.  The `.control` bindings are byte-identical to
    /// what buildSpecs() embeds today.
    static func navigationRawBindings(for modifier: NavigationModifier) -> [String: KeyBinding] {
        switch modifier {
        case .control:
            return [
                "focus.left":                      KeyBinding(keyCode: UInt32(kVK_LeftArrow),  modifiers: UInt32(controlKey)),
                "focus.right":                     KeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey)),
                "focusWindowOrWorkspaceUp":         KeyBinding(keyCode: UInt32(kVK_UpArrow),    modifiers: UInt32(controlKey)),
                "focusWindowOrWorkspaceDown":       KeyBinding(keyCode: UInt32(kVK_DownArrow),  modifiers: UInt32(controlKey)),
                "move.left":                       KeyBinding(keyCode: UInt32(kVK_LeftArrow),  modifiers: UInt32(controlKey | shiftKey)),
                "move.right":                      KeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey | shiftKey)),
                "moveWindowUpOrToWorkspaceUp":      KeyBinding(keyCode: UInt32(kVK_UpArrow),    modifiers: UInt32(controlKey | shiftKey)),
                "moveWindowDownOrToWorkspaceDown":  KeyBinding(keyCode: UInt32(kVK_DownArrow),  modifiers: UInt32(controlKey | shiftKey)),
                // Ctrl+Alt+← / → — the defaultBinding() transform strips optionKey and sets usesHyper=true
                "moveColumn.left":                 KeyBinding(keyCode: UInt32(kVK_LeftArrow),  modifiers: UInt32(controlKey | optionKey)),
                "moveColumn.right":                KeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey | optionKey)),
                "moveColumnToWorkspaceUp":          KeyBinding(keyCode: UInt32(kVK_UpArrow),    modifiers: UInt32(controlKey | optionKey)),
                "moveColumnToWorkspaceDown":        KeyBinding(keyCode: UInt32(kVK_DownArrow),  modifiers: UInt32(controlKey | optionKey))
            ]
        case .option:
            return [
                "focus.left":                      KeyBinding(keyCode: UInt32(kVK_LeftArrow),  modifiers: UInt32(optionKey)),
                "focus.right":                     KeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(optionKey)),
                "focusWindowOrWorkspaceUp":         KeyBinding(keyCode: UInt32(kVK_UpArrow),    modifiers: UInt32(optionKey)),
                "focusWindowOrWorkspaceDown":       KeyBinding(keyCode: UInt32(kVK_DownArrow),  modifiers: UInt32(optionKey)),
                "move.left":                       KeyBinding(keyCode: UInt32(kVK_LeftArrow),  modifiers: UInt32(optionKey | shiftKey)),
                "move.right":                      KeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(optionKey | shiftKey)),
                "moveWindowUpOrToWorkspaceUp":      KeyBinding(keyCode: UInt32(kVK_UpArrow),    modifiers: UInt32(optionKey | shiftKey)),
                "moveWindowDownOrToWorkspaceDown":  KeyBinding(keyCode: UInt32(kVK_DownArrow),  modifiers: UInt32(optionKey | shiftKey)),
                // Opt+Ctrl+← / → — also carries optionKey, so defaultBinding() strips it → usesHyper=true
                "moveColumn.left":                 KeyBinding(keyCode: UInt32(kVK_LeftArrow),  modifiers: UInt32(optionKey | controlKey)),
                "moveColumn.right":                KeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(optionKey | controlKey)),
                "moveColumnToWorkspaceUp":          KeyBinding(keyCode: UInt32(kVK_UpArrow),    modifiers: UInt32(optionKey | controlKey)),
                "moveColumnToWorkspaceDown":        KeyBinding(keyCode: UInt32(kVK_DownArrow),  modifiers: UInt32(optionKey | controlKey))
            ]
        }
    }

    /// Maps an arrow keycode to its Vim (hjkl) equivalent, or nil if `keyCode` is
    /// not one of the four arrow keys.
    private static func vimKeyCode(forArrow keyCode: UInt32) -> UInt32? {
        switch keyCode {
        case UInt32(kVK_LeftArrow): UInt32(kVK_ANSI_H)
        case UInt32(kVK_DownArrow): UInt32(kVK_ANSI_J)
        case UInt32(kVK_UpArrow): UInt32(kVK_ANSI_K)
        case UInt32(kVK_RightArrow): UInt32(kVK_ANSI_L)
        default: nil
        }
    }

    /// Returns the raw navigation KeyBindings for `modifier`, with the keycodes
    /// remapped according to `keymap`.  The Vim keymap swaps ONLY the arrow keycode
    /// for hjkl, preserving each binding's modifiers and usesHyper.
    static func navigationBindings(
        for modifier: NavigationModifier,
        keymap: HotkeyKeymap
    ) -> [String: KeyBinding] {
        let raw = navigationRawBindings(for: modifier)
        guard keymap == .vim else { return raw }
        return raw.mapValues { binding in
            guard let vimCode = vimKeyCode(forArrow: binding.keyCode) else { return binding }
            return KeyBinding(keyCode: vimCode, modifiers: binding.modifiers, usesHyper: binding.usesHyper)
        }
    }

    /// The full default binding list, with navigation defaults derived from `modifier`.
    /// When `modifier == .control` the output is byte-identical to `defaultHotkeyBindings()`.
    static func defaultHotkeyBindings(modifier: NavigationModifier) -> [HotkeyBinding] {
        defaultHotkeyBindings(modifier: modifier, keymap: .arrows)
    }

    /// The full default binding list, with navigation defaults derived from `modifier`
    /// and `keymap`.  When `modifier == .control && keymap == .arrows` the output is
    /// byte-identical to `defaultHotkeyBindings()`.
    static func defaultHotkeyBindings(
        modifier: NavigationModifier,
        keymap: HotkeyKeymap
    ) -> [HotkeyBinding] {
        guard !(modifier == .control && keymap == .arrows) else {
            return defaultHotkeyBindings()
        }
        let raw = navigationBindings(for: modifier, keymap: keymap)
        return specs.map { spec in
            if let rawBinding = raw[spec.id] {
                return HotkeyBinding(
                    id: spec.id,
                    command: spec.command,
                    binding: defaultBinding(for: rawBinding)
                )
            }
            return HotkeyBinding(id: spec.id, command: spec.command, binding: spec.defaultBinding)
        }
    }

    static func defaultHotkeyBindings() -> [HotkeyBinding] {
        specs.map { spec in
            HotkeyBinding(
                id: spec.id,
                command: spec.command,
                binding: spec.defaultBinding
            )
        }
    }

    static func matchesSearch(_ query: String, binding: HotkeyBinding) -> Bool {
        let normalizedQuery = normalizedSearchTerm(query)
        guard !normalizedQuery.isEmpty else { return true }

        guard let spec = spec(for: binding.id) else {
            return binding.command.displayName.localizedCaseInsensitiveContains(query)
                || binding.command.layoutCompatibility.rawValue.localizedCaseInsensitiveContains(query)
                || binding.binding.displayString.localizedCaseInsensitiveContains(query)
                || binding.binding.humanReadableString.localizedCaseInsensitiveContains(query)
        }

        return spec.searchTerms.contains { normalizedSearchTerm($0).contains(normalizedQuery) }
            || normalizedSearchTerm(binding.binding.displayString).contains(normalizedQuery)
            || normalizedSearchTerm(binding.binding.humanReadableString).contains(normalizedQuery)
    }

    static func uniqueTerms(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { raw in
            let normalized = normalizedSearchTerm(raw)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else {
                return nil
            }
            return raw
        }
    }

    static func normalizedSearchTerm(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func buildSpecs() -> [ActionSpec] {
        var specs: [ActionSpec] = []

        // NOTE: switchWorkspace.(idx), moveToWorkspace.(idx), and
        // moveColumnToWorkspace.(idx) numbered-jump specs have been removed.
        // The underlying enum cases are kept for persisted-keymap compatibility.

        specs.append(
            action(
                id: "workspaceBackAndForth",
                command: .workspaceBackAndForth,
                category: .workspace,
                binding: KeyBinding(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey | controlKey)),
                keywords: ["back and forth", "previous workspace"]
            )
        )

        specs.append(contentsOf: [
            action(
                id: "switchWorkspace.next",
                command: .switchWorkspaceNext,
                category: .workspace,
                binding: .unassigned
            ),
            action(
                id: "switchWorkspace.previous",
                command: .switchWorkspacePrevious,
                category: .workspace,
                binding: .unassigned
            )
        ])

        // Focus left/right: Ctrl+←/→
        // Focus up/down: UNASSIGNED (plain in-column; advanced users may rebind)
        // Up/down spill variants are bound below in the focusWindowOrWorkspace* section.
        specs.append(contentsOf: [
            action(
                id: "focus.left",
                command: .focus(.left),
                category: .focus,
                binding: KeyBinding(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey))
            ),
            action(
                id: "focus.down",
                command: .focus(.down),
                category: .focus,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "focus.up",
                command: .focus(.up),
                category: .focus,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "focus.right",
                command: .focus(.right),
                category: .focus,
                binding: KeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey))
            )
        ])

        specs.append(
            action(
                id: "focusPrevious",
                command: .focusPrevious,
                category: .focus,
                binding: KeyBinding(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey)),
                keywords: ["last focused", "recent window"]
            )
        )

        specs.append(contentsOf: [
            action(
                id: "focusDownOrLeft",
                command: .focusDownOrLeft,
                category: .focus,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "focusUpOrRight",
                command: .focusUpOrRight,
                category: .focus,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "focusWindowTop",
                command: .focusWindowTop,
                category: .focus,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "focusWindowBottom",
                command: .focusWindowBottom,
                category: .focus,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "focusWindowDownOrTop",
                command: .focusWindowDownOrTop,
                category: .focus,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "focusWindowUpOrBottom",
                command: .focusWindowUpOrBottom,
                category: .focus,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "focusWindowOrWorkspaceDown",
                command: .focusWindowOrWorkspaceDown,
                category: .focus,
                // Ctrl+↓: focus window below, spilling to the row below at column bottom
                binding: KeyBinding(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(controlKey))
            ),
            action(
                id: "focusWindowOrWorkspaceUp",
                command: .focusWindowOrWorkspaceUp,
                category: .focus,
                // Ctrl+↑: focus window above, spilling to the row above at column top
                binding: KeyBinding(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey))
            )
        ])

        specs.append(contentsOf: [
            action(
                id: "centerColumn",
                command: .centerColumn,
                category: .layout,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "centerVisibleColumns",
                command: .centerVisibleColumns,
                category: .layout,
                binding: .unassigned,
                visibility: .advanced
            )
        ])

        specs.append(contentsOf: [
            // moveWindowToWorkspaceUp/Down: plain "move to adjacent row" without spill.
            // Left unassigned; the spill variants below (moveWindowUpOrToWorkspaceUp/Down)
            // are the primary defaults (Ctrl+Shift+↑/↓).
            action(
                id: "moveWindowToWorkspaceUp",
                command: .moveWindowToWorkspaceUp,
                category: .workspace,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "moveWindowToWorkspaceDown",
                command: .moveWindowToWorkspaceDown,
                category: .workspace,
                binding: .unassigned,
                visibility: .advanced
            ),
            // moveColumnToWorkspaceUp/Down: move the whole column to the row above/below.
            // Ctrl+Alt+↑/↓ (does not collide with Ctrl+Shift+↑/↓ or Ctrl+←/→).
            action(
                id: "moveColumnToWorkspaceUp",
                command: .moveColumnToWorkspaceUp,
                category: .workspace,
                binding: KeyBinding(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey | optionKey))
            ),
            action(
                id: "moveColumnToWorkspaceDown",
                command: .moveColumnToWorkspaceDown,
                category: .workspace,
                binding: KeyBinding(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(controlKey | optionKey))
            )
        ])

        // NOTE: moveColumnToWorkspace.(idx) numbered-jump specs removed.

        // move.left/right: Ctrl+Shift+←/→
        // move.up/down: UNASSIGNED (plain in-column; advanced users may rebind)
        // Up/down spill variants are bound below in the moveWindowUpOrToWorkspace* section.
        specs.append(contentsOf: [
            action(
                id: "move.left",
                command: .move(.left),
                category: .move,
                binding: KeyBinding(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey | shiftKey))
            ),
            action(
                id: "move.down",
                command: .move(.down),
                category: .move,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "move.up",
                command: .move(.up),
                category: .move,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "move.right",
                command: .move(.right),
                category: .move,
                binding: KeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey | shiftKey))
            )
        ])

        specs.append(contentsOf: [
            action(
                id: "moveWindowDown",
                command: .moveWindowDown,
                category: .move,
                binding: .unassigned,
                visibility: .hidden
            ),
            action(
                id: "moveWindowUp",
                command: .moveWindowUp,
                category: .move,
                binding: .unassigned,
                visibility: .hidden
            ),
            action(
                id: "moveWindowDownOrToWorkspaceDown",
                command: .moveWindowDownOrToWorkspaceDown,
                category: .move,
                // Ctrl+Shift+↓: move window down, spilling to the row below at column bottom
                binding: KeyBinding(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(controlKey | shiftKey))
            ),
            action(
                id: "moveWindowUpOrToWorkspaceUp",
                command: .moveWindowUpOrToWorkspaceUp,
                category: .move,
                // Ctrl+Shift+↑: move window up, spilling to the row above at column top
                binding: KeyBinding(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey | shiftKey))
            ),
            action(
                id: "consumeOrExpelWindowLeft",
                command: .consumeOrExpelWindowLeft,
                category: .move,
                binding: .unassigned,
                visibility: .hidden
            ),
            action(
                id: "consumeOrExpelWindowRight",
                command: .consumeOrExpelWindowRight,
                category: .move,
                binding: .unassigned,
                visibility: .hidden
            ),
            action(
                id: "consumeWindowIntoColumn",
                command: .consumeWindowIntoColumn,
                category: .move,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "expelWindowFromColumn",
                command: .expelWindowFromColumn,
                category: .move,
                binding: .unassigned,
                visibility: .advanced
            )
        ])

        specs.append(contentsOf: [
            action(
                id: "focusMonitorNext",
                command: .focusMonitorNext,
                category: .monitor,
                binding: KeyBinding(keyCode: UInt32(kVK_Tab), modifiers: UInt32(controlKey | cmdKey))
            ),
            action(
                id: "focusMonitorPrevious",
                command: .focusMonitorPrevious,
                category: .monitor,
                binding: .unassigned
            ),
            action(
                id: "focusMonitorLast",
                command: .focusMonitorLast,
                category: .monitor,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(controlKey | cmdKey))
            )
        ])

        specs.append(contentsOf: [
            action(
                id: "toggleFullscreen",
                command: .toggleFullscreen,
                category: .layout,
                binding: KeyBinding(keyCode: UInt32(kVK_Return), modifiers: UInt32(optionKey))
            ),
            action(
                id: "toggleNativeFullscreen",
                command: .toggleNativeFullscreen,
                category: .layout,
                binding: .unassigned
            ),
            action(
                id: "moveColumn.left",
                command: .moveColumn(.left),
                category: .column,
                // Ctrl+Alt+← (does not collide with Ctrl+Shift+← or Ctrl+←)
                binding: KeyBinding(
                    keyCode: UInt32(kVK_LeftArrow),
                    modifiers: UInt32(controlKey | optionKey)
                )
            ),
            action(
                id: "moveColumn.right",
                command: .moveColumn(.right),
                category: .column,
                // Ctrl+Alt+→ (does not collide with Ctrl+Shift+→ or Ctrl+→)
                binding: KeyBinding(
                    keyCode: UInt32(kVK_RightArrow),
                    modifiers: UInt32(controlKey | optionKey)
                )
            ),
            action(
                id: "moveColumnToFirst",
                command: .moveColumnToFirst,
                category: .column,
                binding: KeyBinding(keyCode: UInt32(kVK_Home), modifiers: UInt32(optionKey | controlKey))
            ),
            action(
                id: "moveColumnToLast",
                command: .moveColumnToLast,
                category: .column,
                binding: KeyBinding(keyCode: UInt32(kVK_End), modifiers: UInt32(optionKey | controlKey))
            ),
            action(
                id: "toggleColumnTabbed",
                command: .toggleColumnTabbed,
                category: .column,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey))
            ),
            action(
                id: "focusColumnFirst",
                command: .focusColumnFirst,
                category: .focus,
                binding: KeyBinding(keyCode: UInt32(kVK_Home), modifiers: UInt32(optionKey))
            ),
            action(
                id: "focusColumnLast",
                command: .focusColumnLast,
                category: .focus,
                binding: KeyBinding(keyCode: UInt32(kVK_End), modifiers: UInt32(optionKey))
            )
        ])

        for (idx, code) in digitCodes.enumerated() {
            specs.append(
                action(
                    id: "focusColumn.\(idx)",
                    command: .focusColumn(idx),
                    category: .focus,
                    binding: KeyBinding(keyCode: code, modifiers: UInt32(optionKey | controlKey)),
                    visibility: .advanced
                )
            )
        }

        for idx in 1 ... 9 {
            specs.append(
                action(
                    id: "focusWindowInColumn.\(idx)",
                    command: .focusWindowInColumn(idx),
                    category: .focus,
                    binding: .unassigned,
                    visibility: .advanced
                )
            )
        }

        for idx in 1 ... 9 {
            specs.append(
                action(
                    id: "moveColumnToIndex.\(idx)",
                    command: .moveColumnToIndex(idx),
                    category: .column,
                    binding: .unassigned,
                    visibility: .advanced
                )
            )
        }

        specs.append(contentsOf: [
            action(
                id: "cycleColumnWidthForward",
                command: .cycleColumnWidthForward,
                category: .column,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_Period), modifiers: UInt32(optionKey)),
                visibility: .advanced
            ),
            action(
                id: "cycleColumnWidthBackward",
                command: .cycleColumnWidthBackward,
                category: .column,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_Comma), modifiers: UInt32(optionKey)),
                visibility: .advanced
            ),
            action(
                id: "cycleWindowWidthForward",
                command: .cycleWindowWidthForward,
                category: .column,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "cycleWindowWidthBackward",
                command: .cycleWindowWidthBackward,
                category: .column,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "cycleWindowHeightForward",
                command: .cycleWindowHeightForward,
                category: .column,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "cycleWindowHeightBackward",
                command: .cycleWindowHeightBackward,
                category: .column,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "toggleColumnFullWidth",
                command: .toggleColumnFullWidth,
                category: .column,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(optionKey | shiftKey))
            ),
            action(
                id: "expandColumnToAvailableWidth",
                command: .expandColumnToAvailableWidth,
                category: .column,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(optionKey | controlKey)),
                visibility: .advanced
            ),
            action(
                id: "resetWindowHeight",
                command: .resetWindowHeight,
                category: .column,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey | controlKey)),
                visibility: .advanced
            ),
            action(
                id: "setColumnWidth.decrease10Percent",
                command: .setColumnWidth(.adjustProportion(-10)),
                category: .column,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_Minus), modifiers: UInt32(optionKey)),
                visibility: .advanced,
                keywords: ["shrink column", "resize column"]
            ),
            action(
                id: "setColumnWidth.increase10Percent",
                command: .setColumnWidth(.adjustProportion(10)),
                category: .column,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_Equal), modifiers: UInt32(optionKey)),
                visibility: .advanced,
                keywords: ["grow column", "resize column"]
            ),
            action(
                id: "setWindowWidth.decrease10Percent",
                command: .setWindowWidth(.adjustProportion(-10)),
                category: .column,
                binding: .unassigned,
                visibility: .advanced,
                keywords: ["shrink window", "resize window"]
            ),
            action(
                id: "setWindowWidth.increase10Percent",
                command: .setWindowWidth(.adjustProportion(10)),
                category: .column,
                binding: .unassigned,
                visibility: .advanced,
                keywords: ["grow window", "resize window"]
            ),
            action(
                id: "setWindowHeight.decrease10Percent",
                command: .setWindowHeight(.adjustProportion(-10)),
                category: .column,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_Minus), modifiers: UInt32(optionKey | shiftKey)),
                visibility: .advanced,
                keywords: ["shorter window", "resize window"]
            ),
            action(
                id: "setWindowHeight.increase10Percent",
                command: .setWindowHeight(.adjustProportion(10)),
                category: .column,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_Equal), modifiers: UInt32(optionKey | shiftKey)),
                visibility: .advanced,
                keywords: ["taller window", "resize window"]
            ),
            action(
                id: "balanceSizes",
                command: .balanceSizes,
                category: .layout,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(optionKey | shiftKey))
            )
        ])

        specs.append(contentsOf: [
            action(
                id: "openCommandPalette",
                command: .openCommandPalette,
                category: .focus,
                binding: KeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
                keywords: ["palette", "search", "commands", "menu"]
            ),
            action(
                id: "raiseAllFloatingWindows",
                command: .raiseAllFloatingWindows,
                category: .layout,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey | shiftKey)),
                keywords: ["float", "floating", "raise"]
            ),
            action(
                id: "rescueOffscreenWindows",
                command: .rescueOffscreenWindows,
                category: .layout,
                binding: .unassigned,
                keywords: ["rescue", "offscreen", "off-screen"]
            ),
            action(
                id: "toggleFocusedWindowFloating",
                command: .toggleFocusedWindowFloating,
                category: .layout,
                binding: .unassigned,
                keywords: ["float", "floating"]
            ),
            action(
                id: "assignFocusedWindowToScratchpad",
                command: .assignFocusedWindowToScratchpad,
                category: .layout,
                binding: .unassigned,
                keywords: ["scratchpad"]
            ),
            action(
                id: "toggleScratchpadWindow",
                command: .toggleScratchpadWindow,
                category: .layout,
                binding: .unassigned,
                keywords: ["scratchpad"]
            ),
            action(
                id: "toggleWorkspaceBarVisibility",
                command: .toggleWorkspaceBarVisibility,
                category: .focus,
                binding: .unassigned,
                keywords: ["workspace bar", "bar"]
            ),
            action(
                id: "toggleOverview",
                command: .toggleOverview,
                category: .focus,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(optionKey | shiftKey)),
                keywords: ["overview"]
            )
        ])

        return specs
    }

    private static func action(
        id: String,
        command: HotkeyCommand,
        category: HotkeyCategory,
        binding: KeyBinding,
        visibility: HotkeyVisibility = .normal,
        keywords: [String] = []
    ) -> ActionSpec {
        let title = displayName(for: command)
        return ActionSpec(
            id: id,
            command: command,
            title: title,
            keywords: uniqueTerms(keywords + [title, id]),
            category: category,
            visibility: visibility,
            layoutCompatibility: compatibility(for: command),
            defaultBinding: defaultBinding(for: binding)
        )
    }

    private static func defaultBinding(for binding: KeyBinding) -> KeyBinding {
        guard !binding.isUnassigned, !binding.usesHyper, binding.modifiers & UInt32(optionKey) != 0 else {
            return binding
        }
        return KeyBinding(
            keyCode: binding.keyCode,
            modifiers: binding.modifiers & ~UInt32(optionKey),
            usesHyper: true
        )
    }

    private static func compatibility(for command: HotkeyCommand) -> LayoutCompatibility {
        switch command {
        case .moveWindowDown,
             .moveWindowUp,
             .moveWindowDownOrToWorkspaceDown,
             .moveWindowUpOrToWorkspaceUp,
             .consumeOrExpelWindowLeft,
             .consumeOrExpelWindowRight,
             .consumeWindowIntoColumn,
             .expelWindowFromColumn,
             .moveColumn,
             .moveColumnToFirst,
             .moveColumnToLast,
             .moveColumnToIndex,
             .moveColumnToWorkspace,
             .moveColumnToWorkspaceUp,
             .moveColumnToWorkspaceDown,
             .toggleColumnFullWidth,
             .toggleColumnTabbed,
             .cycleWindowWidthForward,
             .cycleWindowWidthBackward,
             .cycleWindowHeightForward,
             .cycleWindowHeightBackward,
             .expandColumnToAvailableWidth,
             .resetWindowHeight,
             .setColumnWidth,
             .setWindowWidth,
             .setWindowHeight,
             .focusPrevious,
             .focusDownOrLeft,
             .focusUpOrRight,
             .focusWindowInColumn,
             .focusWindowTop,
             .focusWindowBottom,
             .focusWindowDownOrTop,
             .focusWindowUpOrBottom,
             .focusWindowOrWorkspaceDown,
             .focusWindowOrWorkspaceUp,
             .focusColumnFirst,
             .focusColumnLast,
             .focusColumn:
            .niri

        case .centerColumn,
             .centerVisibleColumns:
            .niri

        case .focus,
             .toggleFullscreen,
             .cycleColumnWidthForward,
             .cycleColumnWidthBackward,
             .balanceSizes,
             .move,
             .moveToWorkspace,
             .moveWindowToWorkspaceUp,
             .moveWindowToWorkspaceDown,
             .switchWorkspace,
             .switchWorkspaceNext,
             .switchWorkspacePrevious,
             .focusMonitorPrevious,
             .focusMonitorNext,
             .focusMonitorLast,
             .toggleNativeFullscreen,
             .swapWorkspaceWithMonitor,
             .workspaceBackAndForth,
             .focusWorkspaceAnywhere,
             .moveWindowToWorkspaceOnMonitor,
             .openCommandPalette,
             .raiseAllFloatingWindows,
             .rescueOffscreenWindows,
             .toggleFocusedWindowFloating,
             .assignFocusedWindowToScratchpad,
             .toggleScratchpadWindow,
             .toggleWorkspaceBarVisibility,
             .toggleOverview:
            .shared
        }
    }

    private static func displayName(for command: HotkeyCommand) -> String {
        switch command {
        case let .focus(dir): "Focus \(dir.displayName)"
        case .focusPrevious: "Focus Previous Window"
        case let .move(dir): "Move \(dir.displayName)"
        case let .moveToWorkspace(idx): "Move to Workspace \(idx + 1)"
        case .moveWindowToWorkspaceUp: "Move Window to Workspace Up"
        case .moveWindowToWorkspaceDown: "Move Window to Workspace Down"
        case let .moveColumnToWorkspace(idx): "Move Column to Workspace \(idx + 1)"
        case .moveColumnToWorkspaceUp: "Move Column to Workspace Up"
        case .moveColumnToWorkspaceDown: "Move Column to Workspace Down"
        case let .switchWorkspace(idx): "Switch to Workspace \(idx + 1)"
        case .switchWorkspaceNext: "Switch to Next Workspace"
        case .switchWorkspacePrevious: "Switch to Previous Workspace"
        case .focusMonitorPrevious: "Focus Previous Monitor"
        case .focusMonitorNext: "Focus Next Monitor"
        case .focusMonitorLast: "Focus Last Monitor"
        case .toggleFullscreen: "Toggle Fullscreen"
        case .toggleNativeFullscreen: "Toggle Native Fullscreen"
        case let .moveColumn(dir): "Move Column \(dir.displayName)"
        case .moveColumnToFirst: "Move Column to First"
        case .moveColumnToLast: "Move Column to Last"
        case let .moveColumnToIndex(idx): "Move Column to Index \(idx)"
        case .moveWindowDown: "Move Window Down"
        case .moveWindowUp: "Move Window Up"
        case .moveWindowDownOrToWorkspaceDown: "Move Window Down or to Workspace Down"
        case .moveWindowUpOrToWorkspaceUp: "Move Window Up or to Workspace Up"
        case .consumeOrExpelWindowLeft: "Consume or Expel Window Left"
        case .consumeOrExpelWindowRight: "Consume or Expel Window Right"
        case .consumeWindowIntoColumn: "Consume Window into Column"
        case .expelWindowFromColumn: "Expel Window from Column"
        case .toggleColumnTabbed: "Toggle Column Tabbed"
        case .focusDownOrLeft: "Traverse Backward"
        case .focusUpOrRight: "Traverse Forward"
        case let .focusWindowInColumn(idx): "Focus Window \(idx) in Column"
        case .focusWindowTop: "Focus Top Window"
        case .focusWindowBottom: "Focus Bottom Window"
        case .focusWindowDownOrTop: "Focus Down or Top"
        case .focusWindowUpOrBottom: "Focus Up or Bottom"
        case .focusWindowOrWorkspaceDown: "Focus Window or Workspace Down"
        case .focusWindowOrWorkspaceUp: "Focus Window or Workspace Up"
        case .focusColumnFirst: "Focus First Column"
        case .focusColumnLast: "Focus Last Column"
        case let .focusColumn(idx): "Focus Column \(idx + 1)"
        case .centerColumn: "Center Column"
        case .centerVisibleColumns: "Center Visible Columns"
        case .cycleColumnWidthForward: "Cycle Column Width Forward"
        case .cycleColumnWidthBackward: "Cycle Column Width Backward"
        case .cycleWindowWidthForward: "Cycle Window Width Forward"
        case .cycleWindowWidthBackward: "Cycle Window Width Backward"
        case .cycleWindowHeightForward: "Cycle Window Height Forward"
        case .cycleWindowHeightBackward: "Cycle Window Height Backward"
        case .toggleColumnFullWidth: "Toggle Column Full Width"
        case .expandColumnToAvailableWidth: "Expand Column to Available Width"
        case .resetWindowHeight: "Reset Window Height"
        case let .setColumnWidth(change): "Set Column Width \(sizeChangeDisplayName(change))"
        case let .setWindowWidth(change): "Set Window Width \(sizeChangeDisplayName(change))"
        case let .setWindowHeight(change): "Set Window Height \(sizeChangeDisplayName(change))"
        case let .swapWorkspaceWithMonitor(dir): "Swap Workspace with \(dir.displayName) Monitor"
        case .balanceSizes: "Balance Sizes"
        case .workspaceBackAndForth: "Switch to Last Active Workspace"
        case let .focusWorkspaceAnywhere(idx): "Focus Workspace \(idx + 1) Anywhere"
        case let .moveWindowToWorkspaceOnMonitor(wsIdx, monDir): "Move Window to Workspace \(wsIdx + 1) on \(monDir.displayName) Monitor"
        case .openCommandPalette: "Toggle Command Palette"
        case .raiseAllFloatingWindows: "Raise All Floating Windows"
        case .rescueOffscreenWindows: "Rescue Off-Screen Floating Windows"
        case .toggleFocusedWindowFloating: "Toggle Focused Window Floating"
        case .assignFocusedWindowToScratchpad: "Assign Focused Window to Scratchpad"
        case .toggleScratchpadWindow: "Toggle Scratchpad Window"
        case .toggleWorkspaceBarVisibility: "Toggle Workspace Bar"
        case .toggleOverview: "Toggle Overview"
        }
    }

    private static func sizeChangeDisplayName(_ change: NiriSizeChange) -> String {
        switch change {
        case let .setFixed(value):
            "Fixed \(Int(value))px"
        case let .setProportion(value):
            "\(Int(value))%"
        case let .adjustFixed(value):
            "\(value >= 0 ? "+" : "")\(Int(value))px"
        case let .adjustProportion(value):
            "\(value >= 0 ? "+" : "")\(Int(value))%"
        }
    }
}
