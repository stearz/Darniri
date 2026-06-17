import AppKit
import Carbon
@testable import Darniri
import XCTest

/// Unit tests for Phase 5: overview keyboard layout-command dispatch.
///
/// Tests the pure/testable pieces that don't require a live GUI:
/// - Keymap resolution: NSEvent (keyCode + modifier flags) → HotkeyCommand
/// - Hyper binding resolution (Ctrl+Alt+← → moveColumn(.left))
/// - isLayoutRelevantCommand filter
/// - carbonModifiers conversion
@MainActor
final class OverviewKeyboardLayoutTests: XCTestCase {

    // MARK: - carbonModifiers

    func testCarbonModifiers_noModifiers_returnsZero() {
        let result = OverviewInputHandler.carbonModifiers(from: [])
        XCTAssertEqual(result, 0)
    }

    func testCarbonModifiers_control_returnsControlKey() {
        let result = OverviewInputHandler.carbonModifiers(from: .control)
        XCTAssertEqual(result, UInt32(controlKey))
    }

    func testCarbonModifiers_option_returnsOptionKey() {
        let result = OverviewInputHandler.carbonModifiers(from: .option)
        XCTAssertEqual(result, UInt32(optionKey))
    }

    func testCarbonModifiers_shift_returnsShiftKey() {
        let result = OverviewInputHandler.carbonModifiers(from: .shift)
        XCTAssertEqual(result, UInt32(shiftKey))
    }

    func testCarbonModifiers_command_returnsCmdKey() {
        let result = OverviewInputHandler.carbonModifiers(from: .command)
        XCTAssertEqual(result, UInt32(cmdKey))
    }

    func testCarbonModifiers_ctrlShift_returnsBothBits() {
        let result = OverviewInputHandler.carbonModifiers(from: [.control, .shift])
        XCTAssertEqual(result, UInt32(controlKey | shiftKey))
    }

    // MARK: - isLayoutRelevantCommand

    func testIsLayoutRelevantCommand_focusLeft_isRelevant() {
        XCTAssertTrue(OverviewInputHandler.isLayoutRelevantCommand(.focus(.left)))
    }

    func testIsLayoutRelevantCommand_focusRight_isRelevant() {
        XCTAssertTrue(OverviewInputHandler.isLayoutRelevantCommand(.focus(.right)))
    }

    func testIsLayoutRelevantCommand_moveLeft_isRelevant() {
        XCTAssertTrue(OverviewInputHandler.isLayoutRelevantCommand(.move(.left)))
    }

    func testIsLayoutRelevantCommand_moveColumnLeft_isRelevant() {
        XCTAssertTrue(OverviewInputHandler.isLayoutRelevantCommand(.moveColumn(.left)))
    }

    func testIsLayoutRelevantCommand_moveWindowUpOrToWorkspaceUp_isRelevant() {
        XCTAssertTrue(OverviewInputHandler.isLayoutRelevantCommand(.moveWindowUpOrToWorkspaceUp))
    }

    func testIsLayoutRelevantCommand_moveWindowDownOrToWorkspaceDown_isRelevant() {
        XCTAssertTrue(OverviewInputHandler.isLayoutRelevantCommand(.moveWindowDownOrToWorkspaceDown))
    }

    func testIsLayoutRelevantCommand_moveColumnToWorkspaceUp_isRelevant() {
        XCTAssertTrue(OverviewInputHandler.isLayoutRelevantCommand(.moveColumnToWorkspaceUp))
    }

    func testIsLayoutRelevantCommand_moveColumnToWorkspaceDown_isRelevant() {
        XCTAssertTrue(OverviewInputHandler.isLayoutRelevantCommand(.moveColumnToWorkspaceDown))
    }

    func testIsLayoutRelevantCommand_switchWorkspaceNext_isRelevant() {
        XCTAssertTrue(OverviewInputHandler.isLayoutRelevantCommand(.switchWorkspaceNext))
    }

    func testIsLayoutRelevantCommand_switchWorkspacePrevious_isRelevant() {
        XCTAssertTrue(OverviewInputHandler.isLayoutRelevantCommand(.switchWorkspacePrevious))
    }

    func testIsLayoutRelevantCommand_toggleOverview_isNotRelevant() {
        XCTAssertFalse(OverviewInputHandler.isLayoutRelevantCommand(.toggleOverview))
    }

    func testIsLayoutRelevantCommand_openCommandPalette_isNotRelevant() {
        XCTAssertFalse(OverviewInputHandler.isLayoutRelevantCommand(.openCommandPalette))
    }

    func testIsLayoutRelevantCommand_toggleFullscreen_isNotRelevant() {
        XCTAssertFalse(OverviewInputHandler.isLayoutRelevantCommand(.toggleFullscreen))
    }

    func testIsLayoutRelevantCommand_cycleColumnWidthForward_isNotRelevant() {
        XCTAssertFalse(OverviewInputHandler.isLayoutRelevantCommand(.cycleColumnWidthForward))
    }

    // MARK: - resolveLayoutCommand (plain bindings)

    /// Ctrl+← should resolve to focus(.left) via the default bindings.
    func testResolveLayoutCommand_ctrlLeft_resolvesFocusLeft() {
        let bindings = defaultLayoutBindings()
        let command = OverviewInputHandler.resolveLayoutCommand(
            keyCode: UInt32(kVK_LeftArrow),
            modifierFlags: .control,
            bindings: bindings,
            hyperTrigger: .default
        )
        XCTAssertEqual(command, .focus(.left))
    }

    /// Ctrl+→ should resolve to focus(.right).
    func testResolveLayoutCommand_ctrlRight_resolvesFocusRight() {
        let bindings = defaultLayoutBindings()
        let command = OverviewInputHandler.resolveLayoutCommand(
            keyCode: UInt32(kVK_RightArrow),
            modifierFlags: .control,
            bindings: bindings,
            hyperTrigger: .default
        )
        XCTAssertEqual(command, .focus(.right))
    }

    /// Ctrl+Shift+← should resolve to move(.left).
    func testResolveLayoutCommand_ctrlShiftLeft_resolvesMoveLeft() {
        let bindings = defaultLayoutBindings()
        let command = OverviewInputHandler.resolveLayoutCommand(
            keyCode: UInt32(kVK_LeftArrow),
            modifierFlags: [.control, .shift],
            bindings: bindings,
            hyperTrigger: .default
        )
        XCTAssertEqual(command, .move(.left))
    }

    /// Ctrl+Shift+→ should resolve to move(.right).
    func testResolveLayoutCommand_ctrlShiftRight_resolvesMoveRight() {
        let bindings = defaultLayoutBindings()
        let command = OverviewInputHandler.resolveLayoutCommand(
            keyCode: UInt32(kVK_RightArrow),
            modifierFlags: [.control, .shift],
            bindings: bindings,
            hyperTrigger: .default
        )
        XCTAssertEqual(command, .move(.right))
    }

    /// Ctrl+↑ should resolve to focusWindowOrWorkspaceUp.
    func testResolveLayoutCommand_ctrlUp_resolvesFocusWindowOrWorkspaceUp() {
        let bindings = defaultLayoutBindings()
        let command = OverviewInputHandler.resolveLayoutCommand(
            keyCode: UInt32(kVK_UpArrow),
            modifierFlags: .control,
            bindings: bindings,
            hyperTrigger: .default
        )
        XCTAssertEqual(command, .focusWindowOrWorkspaceUp)
    }

    /// Ctrl+↓ should resolve to focusWindowOrWorkspaceDown.
    func testResolveLayoutCommand_ctrlDown_resolvesFocusWindowOrWorkspaceDown() {
        let bindings = defaultLayoutBindings()
        let command = OverviewInputHandler.resolveLayoutCommand(
            keyCode: UInt32(kVK_DownArrow),
            modifierFlags: .control,
            bindings: bindings,
            hyperTrigger: .default
        )
        XCTAssertEqual(command, .focusWindowOrWorkspaceDown)
    }

    /// Ctrl+Shift+↑ should resolve to moveWindowUpOrToWorkspaceUp.
    func testResolveLayoutCommand_ctrlShiftUp_resolvesMoveWindowUpOrToWorkspaceUp() {
        let bindings = defaultLayoutBindings()
        let command = OverviewInputHandler.resolveLayoutCommand(
            keyCode: UInt32(kVK_UpArrow),
            modifierFlags: [.control, .shift],
            bindings: bindings,
            hyperTrigger: .default
        )
        XCTAssertEqual(command, .moveWindowUpOrToWorkspaceUp)
    }

    /// Ctrl+Shift+↓ should resolve to moveWindowDownOrToWorkspaceDown.
    func testResolveLayoutCommand_ctrlShiftDown_resolvesMoveWindowDownOrToWorkspaceDown() {
        let bindings = defaultLayoutBindings()
        let command = OverviewInputHandler.resolveLayoutCommand(
            keyCode: UInt32(kVK_DownArrow),
            modifierFlags: [.control, .shift],
            bindings: bindings,
            hyperTrigger: .default
        )
        XCTAssertEqual(command, .moveWindowDownOrToWorkspaceDown)
    }

    // MARK: - resolveLayoutCommand (hyper / Ctrl+Alt bindings)

    /// Ctrl+Alt+← with Option as hyper trigger: the stored binding has keyCode=leftArrow,
    /// modifiers=controlKey, usesHyper=true.  The NSEvent carries modifiers [.control, .option].
    /// resolveLayoutCommand should strip Option (the hyper trigger) and match usesHyper=true.
    func testResolveLayoutCommand_ctrlOptionLeft_resolvesMoveColumnLeft_withOptionHyper() {
        let bindings = defaultLayoutBindings()
        // Default hyper trigger is .key(kVK_Option), which has modifierMaskToExclude = optionKey.
        let command = OverviewInputHandler.resolveLayoutCommand(
            keyCode: UInt32(kVK_LeftArrow),
            modifierFlags: [.control, .option],
            bindings: bindings,
            hyperTrigger: .key(UInt32(kVK_Option))
        )
        XCTAssertEqual(command, .moveColumn(.left))
    }

    /// Ctrl+Alt+→ with Option as hyper trigger should resolve to moveColumn(.right).
    func testResolveLayoutCommand_ctrlOptionRight_resolvesMoveColumnRight_withOptionHyper() {
        let bindings = defaultLayoutBindings()
        let command = OverviewInputHandler.resolveLayoutCommand(
            keyCode: UInt32(kVK_RightArrow),
            modifierFlags: [.control, .option],
            bindings: bindings,
            hyperTrigger: .key(UInt32(kVK_Option))
        )
        XCTAssertEqual(command, .moveColumn(.right))
    }

    /// Ctrl+Alt+↑ with Option as hyper trigger should resolve to moveColumnToWorkspaceUp.
    func testResolveLayoutCommand_ctrlOptionUp_resolvesMoveColumnToWorkspaceUp_withOptionHyper() {
        let bindings = defaultLayoutBindings()
        let command = OverviewInputHandler.resolveLayoutCommand(
            keyCode: UInt32(kVK_UpArrow),
            modifierFlags: [.control, .option],
            bindings: bindings,
            hyperTrigger: .key(UInt32(kVK_Option))
        )
        XCTAssertEqual(command, .moveColumnToWorkspaceUp)
    }

    /// Ctrl+Alt+↓ with Option as hyper trigger should resolve to moveColumnToWorkspaceDown.
    func testResolveLayoutCommand_ctrlOptionDown_resolvesMoveColumnToWorkspaceDown_withOptionHyper() {
        let bindings = defaultLayoutBindings()
        let command = OverviewInputHandler.resolveLayoutCommand(
            keyCode: UInt32(kVK_DownArrow),
            modifierFlags: [.control, .option],
            bindings: bindings,
            hyperTrigger: .key(UInt32(kVK_Option))
        )
        XCTAssertEqual(command, .moveColumnToWorkspaceDown)
    }

    /// When hyperTrigger is .system (no key exclusion), Ctrl+Alt+← should NOT resolve
    /// as a hyper binding (system hyper requires Ctrl+Alt+Shift+Cmd).
    func testResolveLayoutCommand_ctrlOptionLeft_doesNotMatchHyperBinding_withSystemHyper() {
        let bindings = defaultLayoutBindings()
        let command = OverviewInputHandler.resolveLayoutCommand(
            keyCode: UInt32(kVK_LeftArrow),
            modifierFlags: [.control, .option],
            bindings: bindings,
            hyperTrigger: .system
        )
        // .system hyper has modifierMaskToExclude=0, so hyper candidate is nil.
        // The stored binding for moveColumn.left is usesHyper=true, modifiers=controlKey.
        // The plain candidate is modifiers=(ctrl|opt), usesHyper=false → no match.
        // So the result should be nil (no matching layout command).
        XCTAssertNil(command)
    }

    /// An unbound key (one not in any registered binding) returns nil.
    func testResolveLayoutCommand_unmatchedKey_returnsNil() {
        let bindings = defaultLayoutBindings()
        let command = OverviewInputHandler.resolveLayoutCommand(
            keyCode: UInt32(kVK_ANSI_Z),
            modifierFlags: [.control, .shift],
            bindings: bindings,
            hyperTrigger: .default
        )
        XCTAssertNil(command)
    }

    // MARK: - keyHandlingResult integration

    /// Plain arrow keys without modifiers should still produce .navigate, not .layoutCommand.
    func testKeyHandlingResult_plainLeftArrow_producesNavigateLeft() {
        let bindings = defaultLayoutBindings()
        let result = OverviewInputHandler.keyHandlingResult(
            keyCode: UInt16(kVK_LeftArrow),
            modifierFlags: [],
            charactersIgnoringModifiers: nil,
            searchQuery: "",
            layoutBindings: bindings,
            hyperTrigger: .default
        )
        XCTAssertEqual(result.action, .navigate(.left))
        XCTAssertTrue(result.shouldConsume)
    }

    /// Ctrl+← should produce .layoutCommand(.focus(.left)), not plain navigation.
    func testKeyHandlingResult_ctrlLeft_producesLayoutCommandFocusLeft() {
        let bindings = defaultLayoutBindings()
        let result = OverviewInputHandler.keyHandlingResult(
            keyCode: UInt16(kVK_LeftArrow),
            modifierFlags: .control,
            charactersIgnoringModifiers: nil,
            searchQuery: "",
            layoutBindings: bindings,
            hyperTrigger: .default
        )
        XCTAssertEqual(result.action, .layoutCommand(.focus(.left)))
        XCTAssertTrue(result.shouldConsume)
    }

    /// Ctrl+Shift+↑ should produce .layoutCommand(.moveWindowUpOrToWorkspaceUp).
    func testKeyHandlingResult_ctrlShiftUp_producesMoveWindowUpOrToWorkspaceUp() {
        let bindings = defaultLayoutBindings()
        let result = OverviewInputHandler.keyHandlingResult(
            keyCode: UInt16(kVK_UpArrow),
            modifierFlags: [.control, .shift],
            charactersIgnoringModifiers: nil,
            searchQuery: "",
            layoutBindings: bindings,
            hyperTrigger: .default
        )
        XCTAssertEqual(result.action, .layoutCommand(.moveWindowUpOrToWorkspaceUp))
        XCTAssertTrue(result.shouldConsume)
    }

    /// Ctrl+Alt+← with Option hyper should produce .layoutCommand(.moveColumn(.left)).
    func testKeyHandlingResult_ctrlOptionLeft_producesMoveColumnLeft() {
        let bindings = defaultLayoutBindings()
        let result = OverviewInputHandler.keyHandlingResult(
            keyCode: UInt16(kVK_LeftArrow),
            modifierFlags: [.control, .option],
            charactersIgnoringModifiers: nil,
            searchQuery: "",
            layoutBindings: bindings,
            hyperTrigger: .key(UInt32(kVK_Option))
        )
        XCTAssertEqual(result.action, .layoutCommand(.moveColumn(.left)))
        XCTAssertTrue(result.shouldConsume)
    }

    /// Escape should still produce .clearSearchOrDismiss even with bindings present.
    func testKeyHandlingResult_escape_producesClearSearchOrDismiss() {
        let bindings = defaultLayoutBindings()
        let result = OverviewInputHandler.keyHandlingResult(
            keyCode: UInt16(kVK_Escape),
            modifierFlags: [],
            charactersIgnoringModifiers: nil,
            searchQuery: "",
            layoutBindings: bindings,
            hyperTrigger: .default
        )
        XCTAssertEqual(result.action, .clearSearchOrDismiss)
    }

    /// With empty bindings list, a modified key event produces .consume (not a layout command).
    func testKeyHandlingResult_noBindings_ctrlLeft_producesConsume() {
        let result = OverviewInputHandler.keyHandlingResult(
            keyCode: UInt16(kVK_LeftArrow),
            modifierFlags: .control,
            charactersIgnoringModifiers: nil,
            searchQuery: "",
            layoutBindings: [],
            hyperTrigger: .default
        )
        XCTAssertEqual(result.action, .consume)
        XCTAssertTrue(result.shouldConsume)
    }

    // MARK: - Helpers

    /// Returns the default layout bindings (filtered to layout-relevant commands) using
    /// the .control navigation modifier — matching the default user configuration.
    private func defaultLayoutBindings() -> [HotkeyBinding] {
        let all = ActionCatalog.defaultHotkeyBindings(modifier: .control)
        return all.filter { OverviewInputHandler.isLayoutRelevantCommand($0.command) }
    }
}
